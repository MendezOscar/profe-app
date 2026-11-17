// Marca el sistema del teléfono (para destacar su tienda) y esconde el botón de WhatsApp
// mientras se ve la portada en pantallas angostas. Sin esto la página funciona igual.
(() => {
  const ua = navigator.userAgent;
  const ios = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const so = ios ? 'ios' : /Android/.test(ua) ? 'android' : null;
  if (so) document.documentElement.classList.add(so);

  const wa = document.querySelector('.wa-flotante');
  const portada = document.querySelector('.portada');
  if (!wa || !portada || !('IntersectionObserver' in window)) return;
  let enPortada = true;
  const aplicar = () => wa.classList.toggle('oculto', enPortada && window.innerWidth <= 760);
  new IntersectionObserver(([e]) => {
    enPortada = e.isIntersecting;
    aplicar();
  }, { threshold: 0.35 }).observe(portada);
  window.addEventListener('resize', aplicar);
})();
