FROM bench-base:ubuntu-24.04
WORKDIR /app

# All toolchains are installed at image build time (apt only; no pip, so the
# image stays lean). Coq, R, sympy, and a minimal TeX Live with pdflatex.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        coq \
        r-base \
        python3-sympy \
        texlive-latex-base \
        texlive-latex-recommended \
        texlive-fonts-recommended \
    && rm -rf /var/lib/apt/lists/*

# The client ships one machine-checked Coq proof that is deliberately
# incomplete; the consultant completes it during the task.
COPY files/ /app/