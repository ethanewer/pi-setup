#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
mkdir -p /home/user/logs
# Generate logs for 5 nodes
for node in $(seq 1 5); do
    > /home/user/logs/node_${node}.log
    loss=1.0
    for epoch in $(seq 1 100); do
        # simulate convergence
        loss=$(echo "$loss * 0.95" | bc -l)
        if [ "$node" -eq 4 ] && [ "$epoch" -ge 51 ]; then
            # Inject comma decimal and scientific notation for Node 4
            formatted_loss=$(printf "%.5e" "$loss" | sed 's/\./,/')
            echo "Epoch: $epoch | Loss: $formatted_loss | Node: $node" >> /home/user/logs/node_${node}.log
        else
            formatted_loss=$(printf "%.6f" "$loss")
            echo "Epoch: $epoch | Loss: $formatted_loss | Node: $node" >> /home/user/logs/node_${node}.log
        fi
    done
done
# Create buggy aggregate.sh
cat << 'EOF' > /home/user/aggregate.sh
#!/bin/bash
# Aggregates losses
for epoch in {1..100}; do
    grep -h "Epoch: $epoch |" /home/user/logs/node_*.log | \
    awk '{
        # Column 5 is the loss value
        sum += $5
        count++
    } END {
        if (count > 0) printf "Epoch %d: %.6f\n", '"$epoch"', sum/count
    }'
done
EOF
rm -rf /home/user/.setup_tmp
