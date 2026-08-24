# Sales Data Aggregator

## Your Task

You are given a text file containing sales records from a small store. Each line represents one transaction with the format:
`item_name,category,price,quantity`

Your job is to process this file and create a summary report in JSON format.

## Requirements

1. **Read the input file** located at `/app/sales.txt`
2. **Process each line**:
   - Skip any lines that don't have exactly 4 comma-separated values
   - Convert price and quantity to numbers (float and int respectively)
   - Skip any lines where price or quantity cannot be converted to numbers
3. **Calculate statistics**:
   - Total revenue (sum of price × quantity for all valid transactions)
   - Average transaction value (total revenue / number of valid transactions)
   - Number of invalid lines skipped
4. **Generate category summary**:
   - For each category, calculate:
     - Total items sold (sum of quantity)
     - Total revenue from that category
     - Average price per item in that category (revenue / items sold)
5. **Write the output** to `/app/summary.json` with this exact structure:
```json
{
  "overall": {
    "total_revenue": 1234.56,
    "average_transaction": 45.67,
    "valid_transactions": 100,
    "invalid_lines": 5
  },
  "categories": {
    "electronics": {
      "items_sold": 50,
      "revenue": 1000.00,
      "avg_price_per_item": 20.00
    },
    "clothing": {
      "items_sold": 30,
      "revenue": 600.00,
      "avg_price_per_item": 20.00
    }
  }
}
```

## Expected Outputs
- **File path**: `/app/summary.json`
- **Format**: Valid JSON with the structure shown above
- **Content**: Contains "overall" and "categories" sections with calculated statistics

## Test Verification
The tests will:
1. Check that `/app/summary.json` exists and is valid JSON
2. Verify all required fields are present with correct data types
3. Validate the calculated values match the input data (rounded to 2 decimal places)