#!/usr/bin/env python3
"""ocr.py — OCR scanned documents (JPG/PNG/PDF) and label each as an
'invoice' (its text carries both an INVOICE mark and a TOTAL figure) or
'other'. Emits {filename: 'invoice'|'other'} sorted by filename.

Usage:  python3 /app/ocr.py [input_dir] [output_json]
Defaults: input /app/scans , output /app/invoice-labels.json
"""
import json, os, re, subprocess, sys, tempfile

def ocr_img_tesseract(path):
    out = subprocess.run(
        ["tesseract", path, "stdout", "--psm", "6"],
        capture_output=True, text=True)
    return out.stdout

def ocr_pdf(pdf_path):
    with tempfile.TemporaryDirectory() as td:
        rast = os.path.join(td, "page")
        subprocess.run(
            ["pdftoppm", "-png", "-r", "150", "-f", "1", "-l", "1",
             pdf_path, rast],
            check=False, capture_output=True)
        cands = sorted(n for n in os.listdir(td) if n.endswith(".png"))
        if not cands:
            return ""
        return ocr_img_tesseract(os.path.join(td, cands[0]))

def doc_text(path):
    if path.lower().endswith(".pdf"):
        return ocr_pdf(path)
    return ocr_img_tesseract(path)

RE_INVOICE = re.compile(r"\bINVOICE\b", re.I)
RE_TOTAL   = re.compile(r"\bTOTAL\b.{0,12}\d", re.I | re.S)

def is_invoice(text):
    return bool(RE_INVOICE.search(text) and RE_TOTAL.search(text))

def classify_dir(input_dir):
    files = sorted(n for n in os.listdir(input_dir)
                   if n.lower().endswith((".jpg", ".jpeg", ".png", ".pdf")))
    labels = {}
    for n in files:
        txt = doc_text(os.path.join(input_dir, n))
        labels[n] = "invoice" if is_invoice(txt) else "other"
    return labels

def main():
    input_dir = sys.argv[1] if len(sys.argv) > 1 else "/app/scans"
    out_json = sys.argv[2] if len(sys.argv) > 2 else "/app/invoice-labels.json"
    labels = classify_dir(input_dir)
    with open(out_json, "w") as fh:
        json.dump(labels, fh, indent=2, sort_keys=True)

if __name__ == "__main__":
    main()