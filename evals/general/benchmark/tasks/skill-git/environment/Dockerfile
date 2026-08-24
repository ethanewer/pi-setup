FROM bench-base:ubuntu-24.04

WORKDIR /app

# No prebuilt repo: the agent initializes /app/repo themselves.
RUN git config --global user.name "Harbor Agent"
RUN git config --global user.email "harbor@example.com"