FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*
RUN pip install pillow