// Quita la pantalla de arranque en cuanto Flutter pinta su primer cuadro.
window.addEventListener('flutter-first-frame', function () {
  document.getElementById('arranque')?.remove();
});
