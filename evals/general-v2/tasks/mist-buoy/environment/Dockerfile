FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN mkdir -p /logs/verifier

# Keep the visible archive instance running for the agent session; the
# verifier re-starts instances itself if needed.
CMD ["bash", "-c", "python3 /app/server.py /app/data/visible.json 8098 >>/tmp/server_visible.log 2>&1 & exec sleep infinity"]
