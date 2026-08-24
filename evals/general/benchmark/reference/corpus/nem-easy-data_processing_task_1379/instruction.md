# Sales Data Aggregation and Reporting Task

You need to process sales transaction data and generate a summary report. This task tests basic data transformation and aggregation skills.

## Input Data

You are given a CSV file at `/app/sales_data.csv` with the following columns:
- `transaction_id`: Unique identifier for each transaction (string)
- `product_id`: Product identifier (string)
- `product_name`: Name of the product (string)
- `category`: Product category (string)
- `quantity`: Number of units sold (integer)
- `unit_price`: Price per unit (float with 2 decimal places)
- `date`: Transaction date in YYYY-MM-DD format (string)

## Your Task

1. **Read and parse the CSV file** from `/app/sales_data.csv`
2. **Filter the data** to include only transactions from the "Electronics" category
3. **Calculate total revenue** for each product (quantity × unit_price)
4. **Aggregate the data** to create a summary with:
   - Product name
   - Total quantity sold
   - Total revenue (rounded to 2 decimal places)
5. **Sort the results** by total revenue in descending order (highest revenue first)
6. **Write the output** to `/app/electronics_summary.json` in the following JSON format:
   ```json
   {
     "category": "Electronics",
     "total_products": <number of unique electronics products>,
     "summary_date": <today's date in YYYY-MM-DD format>,
     "products": [
       {
         "product_name": "Product A",
         "total_quantity": 100,
         "total_revenue": 1500.50
       },
       ...
     ]
   }
   ```

## Expected Outputs

- **Primary output**: `/app/electronics_summary.json` - JSON file with the aggregated summary
- The JSON must be properly formatted and valid (parsable by `json.load()`)
- The `summary_date` must be today's date (use current system date)
- Products must be sorted by `total_revenue` descending
- Only include products from the "Electronics" category
- All revenue values must be rounded to 2 decimal places

## Example

Given input like:
```
transaction_id,product_id,product_name,category,quantity,unit_price,date
T001,P101,Laptop,Electronics,2,899.99,2024-01-15
T002,P102,T-Shirt,Clothing,5,19.99,2024-01-15
T003,P103,Smartphone,Electronics,3,699.99,2024-01-16
```

Your output should look like:
```json
{
  "category": "Electronics",
  "total_products": 2,
  "summary_date": "2024-01-20",
  "products": [
    {
      "product_name": "Laptop",
      "total_quantity": 2,
      "total_revenue": 1799.98
    },
    {
      "product_name": "Smartphone",
      "total_quantity": 3,
      "total_revenue": 2099.97
    }
  ]
}
```

**Note**: The tests will verify that your output file exists, contains valid JSON, has the correct structure, and the data is correctly aggregated and sorted.