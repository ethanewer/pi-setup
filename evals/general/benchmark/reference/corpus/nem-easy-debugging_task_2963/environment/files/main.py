#!/usr/bin/env python3
"""
CSV Validator - Validates CSV files against a schema configuration.
Usage: python3 main.py
"""

import json
import csv
import os
from pathlib import Path

def load_schema(schema_path):
    """Load validation schema from JSON file."""
    with open(schema_path, 'r') as f:
        return json.load(f)

def validate_field(value, field_schema):
    """Validate a single field against its schema."""
    field_type = field_schema.get('type', 'string')
    
    # Handle empty values
    if not value and field_schema.get('required', False):
        return False, "Required field is empty"
    
    # Type validation
    if field_type == 'integer':
        try:
            int_value = int(value)
            if 'min' in field_schema and int_value < field_schema['min']:
                return False, f"Value must be >= {field_schema['min']}"
            if 'max' in field_schema and int_value > field_schema['max']:
                return False, f"Value must be <= {field_schema['max']}"
        except ValueError:
            return False, "Value must be integer"
    
    elif field_type == 'float':
        try:
            float(value)
        except ValueError:
            return False, "Value must be float"
    
    elif field_type == 'email':
        if '@' not in value or '.' not in value:
            return False, "Invalid email format"
    
    elif field_type == 'boolean':
        if value.lower() not in ['true', 'false', 'yes', 'no', '1', '0']:
            return False, "Value must be boolean"
    
    return True, ""

def validate_csv(input_path, schema):
    """Validate CSV file against schema."""
    results = {
        'total_records': 0,
        'valid_records': 0,
        'invalid_records': 0,
        'errors': []
    }
    
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        
        for line_num, row in enumerate(reader, start=1):
            results['total_records'] += 1
            record_valid = True
            
            for field_name, field_schema in schema['fields'].items():
                value = row.get(field_name, '')
                
                # Special handling for optional fields
                if not value and not field_schema.get('required', True):
                    continue
                
                # BUG: This condition is reversed!
                if field_schema.get('type') == 'integer' and field_schema.get('required'):
                    if not value:  # This should check if value is empty
                        is_valid, error_msg = False, "Required integer field is empty"
                    else:
                        is_valid, error_msg = validate_field(value, field_schema)
                else:
                    is_valid, error_msg = validate_field(value, field_schema)
                
                if not is_valid:
                    record_valid = False
                    results['errors'].append({
                        'line_number': line_num,
                        'field': field_name,
                        'error': error_msg
                    })
                    # Only report first error per record for clarity
                    break
            
            if record_valid:
                results['valid_records'] += 1
            else:
                results['invalid_records'] += 1
    
    return results

def main():
    """Main validation routine."""
    # Paths
    schema_path = '/app/config/schema.json'
    input_path = '/app/data/input.csv'
    output_dir = '/app/output'
    output_path = os.path.join(output_dir, 'validation_report.json')
    
    # Ensure output directory exists
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Load schema
    schema = load_schema(schema_path)
    
    # Validate CSV
    print(f"Validating {input_path} against schema...")
    results = validate_csv(input_path, schema)
    
    # Save results
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"Validation complete!")
    print(f"Total records: {results['total_records']}")
    print(f"Valid records: {results['valid_records']}")
    print(f"Invalid records: {results['invalid_records']}")
    print(f"Results saved to: {output_path}")

if __name__ == '__main__':
    main()