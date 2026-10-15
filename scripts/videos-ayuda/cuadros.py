# Cuadros de SACE inventados para los videos: centro, alumnos e identidades (prefijo 9999) ficticios.
import random, zipfile, os
os.chdir(os.path.dirname(os.path.abspath(__file__))); os.makedirs('cuadros', exist_ok=True)
from xml.sax.saxutils import escape
random.seed(7)
ellas=[['ANA','MARÍA','CARLA','SOFÍA','DANIELA','VALERIA','GABRIELA','PAOLA','NICOLE','KARLA','FERNANDA','MELISSA','ALEJANDRA','KATHERINE'],['ISABEL','FERNANDA','LUCÍA','MICHELLE','BEATRIZ','NAHOMY','GUADALUPE','ALEJANDRA','SARAÍ','PATRICIA']]
ellos=[['LUIS','JOSÉ','DIEGO','KEVIN','JORGE','MARIO','ÁNGEL','BRYAN','JUAN','ERICK','OSCAR','DAVID','JOSUÉ','CARLOS'],['ANTONIO','DAVID','ENRIQUE','ALBERTO','MANUEL','ALEJANDRO','FRANCISCO','JOSUÉ','ANDRÉS','RICARDO']]
apellidos=['LÓPEZ','MARTÍNEZ','RODRÍGUEZ','HERNÁNDEZ','MEJÍA','CASTRO','ORTEGA','PAZ','REYES','ZELAYA','SIERRA','PINEDA','ROMERO','FLORES','AGUILAR','CÁRCAMO','VELÁSQUEZ','MORALES','ALVARADO','BANEGAS']
def col(i):
  return 'ABCDEFGHIJKLMNOP'[i]
def cuadro(path, grado, n, codigo):
  c={}
  c['A1']=f'{codigo} | INSTITUTO DE PRUEBAS'
  c['A2']='MODALIDAD: TERCER CICLO DE EDUCACIÓN BÁSICA'
  c['A3']=grado; c['A4']='JORNADA MATUTINA'; c['A5']='CIENCIAS NATURALES'
  c['A6']='DOCUMENTO'; c['B6']='IDENTIDAD'; c['C6']='NOMBRE'
  for k,p in enumerate(['PARCIAL I','PARCIAL II','PARCIAL III','PARCIAL IV']):
    c[f'{col(3+2*k)}6']=p; c[f'{col(3+2*k)}7']='INASISTENCIAS'; c[f'{col(4+2*k)}7']='NOTA TOTAL'
  c['L6']='RECUPERACIÓN'
  usados=set(); fila=8; alumnos=[]
  while len(alumnos)<n:
    g=random.choice([ellas,ellos]); a,b=random.choice(g[0]),random.choice(g[1]); ap1,ap2=random.sample(apellidos,2)
    if a==b: continue
    nom=f'{a} {b} {ap1} {ap2}'
    if nom in usados: continue
    usados.add(nom); alumnos.append(nom)
  for nom in sorted(alumnos):
    c[f'A{fila}']='HND'; c[f'B{fila}']='9999'+''.join(random.choice('0123456789') for _ in range(9)); c[f'C{fila}']=nom; fila+=1
  c[f'A{fila}']='**********Fin del documento**********'
  c[f'A{fila+1}']='Nota: Únicamente ingrese notas en las casillas generadas por el sistema para este documento.'
  merges=['A1:L1','A2:L2','A3:L3','A4:L4','A5:L5','A6:A7','B6:B7','C6:C7','D6:E6','F6:G6','H6:I6','J6:K6','L6:L7',f'A{fila}:L{fila}',f'A{fila+1}:L{fila+1}']
  textos=[]; filas={}
  for ref,v in c.items():
    r=int(''.join(ch for ch in ref if ch.isdigit()))
    textos.append(v); filas.setdefault(r,[]).append(f'<c r="{ref}" t="s"><v>{len(textos)-1}</v></c>')
  sd=''.join(f'<row r="{r}">{"".join(filas[r])}</row>' for r in sorted(filas))
  ns='xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
  nsr='xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
  with zipfile.ZipFile(path,'w') as z:
    z.writestr('[Content_Types].xml','<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>')
    z.writestr('_rels/.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    z.writestr('xl/workbook.xml',f'<?xml version="1.0"?><workbook {ns} {nsr}><sheets><sheet name="{codigo}" sheetId="1" r:id="rId1"/></sheets></workbook>')
    z.writestr('xl/_rels/workbook.xml.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>')
    z.writestr('xl/sharedStrings.xml',f'<?xml version="1.0"?><sst {ns}>'+''.join(f'<si><t>{escape(t)}</t></si>' for t in textos)+'</sst>')
    z.writestr('xl/worksheets/sheet1.xml',f'<?xml version="1.0"?><worksheet {ns}><sheetData>{sd}</sheetData><mergeCells count="{len(merges)}">'+''.join(f'<mergeCell ref="{m}"/>' for m in merges)+'</mergeCells></worksheet>')
cuadro('cuadros/CIENCIAS_NATURALES_SECCION_1.xlsx','SÉPTIMO GRADO SECCIÓN 1',24,'999900001M01')
cuadro('cuadros/CIENCIAS_NATURALES_SECCION_2.xlsx','SÉPTIMO GRADO SECCIÓN 2',22,'999900001M02')
