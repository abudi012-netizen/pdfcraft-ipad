# PdfCraft Pad

An iPad study reader inspired by PdfCraft: a lecture library, search across every PDF, night reading, and Apple Pencil notes.

## Stage 1 features
- **Library** – import PDFs from Files (or drop them into *On My iPad › PdfCraft Pad*). Long-press a lecture to delete it.
- **Search all PDFs** – find a drug name or term in every lecture, grouped by PDF, and jump straight to each mention.
- **Find in PDF** – the same search inside the open lecture.
- **Night reading** – inverts the pages; your Pencil ink keeps its real colors.
- **Apple Pencil** – tap the pencil button: pen, pencil, marker, eraser, lasso, ruler and colors from Apple's tool palette. Pencil draws, fingers keep scrolling and zooming. Notes save automatically per page.
- **Remembers your place** in each lecture.
- App-wide Light / Dark / System appearance.

## Coming next
- Stage 2: hide-label tool (manual) and auto hide labels
- Stage 3: highlights summary and side-by-side PDFs

## How it's built
GitHub Actions builds an unsigned `.ipa` on every push to `main` and attaches it to the **latest** release. Open that `.ipa` in SideStore on the iPad; SideStore signs it with your free Apple ID and renews it every 7 days.

## Medical dictionary
Offline definitions for drugs, diseases and terms, plus each drug's pharmacological class. Select a word in a PDF and tap **Medical Dictionary** (in the selection menu or the toolbar), or open it from the library. Built at compile time from MeSH, courtesy of the U.S. National Library of Medicine.
