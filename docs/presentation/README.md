# ViaX product overview

- [Editable PowerPoint](ViaX-Overview.pptx)
- [PDF for viewing and sharing](ViaX-Overview.pdf)
- [Individual slide images](../media/)

Six slides introduce the product, study workflow, desktop and mobile chat, architecture, and open-source project. Text in the PowerPoint is editable. Screenshots and cover artwork are embedded images. The PDF uses fixed slide images to preserve the layout.

The generation source is `scripts/build-presentation.mjs`, authored with the Codex presentation runtime's `@oai/artifact-tool`. It requires that runtime and `VIA_X_RUNTIME_MODULES` pointing to its `node_modules` directory. `scripts/export-slide-pdf.py` assembles the rendered PNGs using ReportLab. The exported files can be used without either tool.

Asset provenance is recorded in [the visual asset notes](../media/README.md) and the PowerPoint's speaker notes.
