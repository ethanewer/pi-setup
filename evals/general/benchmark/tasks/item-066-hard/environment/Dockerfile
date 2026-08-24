FROM bench-base:python-3.12

WORKDIR /app

# item-066: corrupted heterogeneous MobileSAM mask consolidation (hard)
# PyTorch (CPU wheels) for MobileSAM-style .pt logit tensors,
# numpy/Pillow for raster work, opencv-python-headless for polygon extraction.
RUN pip install --no-cache-dir "numpy==1.26.4" "pillow>=10,<12" "opencv-python-headless==4.10.0.84" \
 && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu "torch==2.4.1"

COPY files/ /app/
RUN python3 /app/make_annotations2.py /app/data

# Agent output goes to /app/out (created by the agent's consolidator).
CMD ["/bin/bash"]