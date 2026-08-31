FROM bench-base:python-3.12

WORKDIR /app

# A sample chunk vault (reshard of an original file tree), used as read-only
# reference input. The original tree is NOT shipped anywhere in the image.
COPY files/ /app/

CMD ["bash"]
