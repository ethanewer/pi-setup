FROM bench-base:python-3.12

WORKDIR /app

RUN printf 'def scaled_value(value, config):\n    return value * config["multiplier"] + config["offset"]\n' > /app/codegtool.py