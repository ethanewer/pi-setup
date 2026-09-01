# Task Dockerfile for willow-quill.
#
# Base: python-3.12. Ships only the visible script fixture; all deliverables
# are authored by the agent at runtime. No network at run/verify time.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
