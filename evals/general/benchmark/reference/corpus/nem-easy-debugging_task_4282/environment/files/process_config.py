import json

def main():
    # Read configuration file
    with open('/app/config.json', 'r') as f:
        config = json.load(f)
    
    # Extract values from configuration
    values = config['values']  # This line causes an error
    total = sum(values)
    average = total / len(values)
    
    # Write output
    with open('/app/output.txt', 'w') as f:
        f.write(f"Total: {total}, Average: {average}")

if __name__ == "__main__":
    main()