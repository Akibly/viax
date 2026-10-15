"""Create a fixed-layout PDF from the rendered slides (requires reportlab)."""
from pathlib import Path
from reportlab.pdfgen import canvas

root = Path(__file__).resolve().parent.parent
slides = sorted((root / 'docs/media').glob('slide-*.png'))
if not slides:
    raise SystemExit('Render the presentation slides first.')
pdf = canvas.Canvas(str(root / 'docs/presentation/ViaX-Overview.pdf'), pagesize=(960, 540))
pdf.setTitle('ViaX - Product Overview')
for slide in slides:
    pdf.drawImage(str(slide), 0, 0, width=960, height=540)
    pdf.showPage()
pdf.save()
