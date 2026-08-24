## Transaction Summary Generator

You are tasked with processing financial transaction data from a JSON file and generating a formatted summary report.

## Your Task

1. **Read Input Data**: Read transaction data from `/app/transactions.json`. This file contains an array of transaction objects, each with:
   - `id`: unique identifier (string)
   - `amount`: transaction amount (float)
   - `category`: transaction category (string)
   - `date`: transaction date in YYYY-MM-DD format (string)

2. **Calculate Summary Statistics**:
   - Count total number of transactions
   - Calculate the total amount of all transactions
   - Find the average transaction amount
   - Count how many transactions have amount greater than 100.00
   - For each unique category, calculate the total amount for that category

3. **Generate Output Files**:
   - Create `/app/summary.txt` containing:
     ```
     Total Transactions: {count}
     Total Amount: ${total:.2f}
     Average Transaction: ${average:.2f}
     Transactions > $100: {count_over_100}
     ```
   - Create `/app/category_totals.csv` containing category summaries with headers:
     ```
     Category,Total_Amount,Transaction_Count
     ```
     Sorted alphabetically by category name

4. **Data Validation**:
   - Skip any transactions with missing or invalid `amount` fields
   - If a transaction has an empty or missing `category`, use "Uncategorized"

## Expected Outputs

- `/app/summary.txt`: Text file with 4 lines as shown above
- `/app/category_totals.csv`: CSV file with 3 columns (Category, Total_Amount, Transaction_Count), sorted by Category

## Example

Given input:
```json
[
  {"id": "T1", "amount": 50.00, "category": "Food", "date": "2024-01-15"},
  {"id": "T2", "amount": 120.50, "category": "Shopping", "date": "2024-01-16"},
  {"id": "T3", "amount": 30.00, "category": "Food", "date": "2024-01-17"},
  {"id": "T4", "amount": 75.25, "category": "", "date": "2024-01-18"}
]
```

Expected summary.txt:
```
Total Transactions: 4
Total Amount: $275.75
Average Transaction: $68.94
Transactions > $100: 1
```

Expected category_totals.csv:
```
Category,Total_Amount,Transaction_Count
Food,80.00,2
Shopping,120.50,1
Uncategorized,75.25,1
```