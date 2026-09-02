FROM bench-base:python-3.12

WORKDIR /app

# Synthetic model-size -> accuracy data (params in millions, accuracy in %).
RUN cat > /app/models.csv <<'EOF'
model,params_m,accuracy_pct
tiny,1,80.1
small,8,84.5
med,64,89.2
large,512,90.1
EOF