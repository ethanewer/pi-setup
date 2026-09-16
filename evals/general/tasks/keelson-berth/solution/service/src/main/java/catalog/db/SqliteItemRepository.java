package catalog.db;

import catalog.model.Item;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * ItemRepository backed by SQLite through the JDBC driver.
 *
 * The repository owns the schema: it creates the {@code items} table on
 * first use (idempotently) and caches the small set of prepared statements
 * for the service's lifetime.  No hand-written SQL lives anywhere else.
 */
public final class SqliteItemRepository implements ItemRepository {

    private static final String CREATE_TABLE =
            "CREATE TABLE IF NOT EXISTS items ("
            + " sku TEXT PRIMARY KEY,"
            + " title TEXT NOT NULL,"
            + " price REAL NOT NULL,"
            + " quantity INTEGER NOT NULL,"
            + " category TEXT NOT NULL)";

    private static final String SELECT_ALL =
            "SELECT sku, title, price, quantity, category FROM items ORDER BY sku";

    private static final String SELECT_BY_CATEGORY =
            "SELECT sku, title, price, quantity, category"
            + " FROM items WHERE category = ? ORDER BY sku";

    private static final String SELECT_BY_SKU =
            "SELECT sku, title, price, quantity, category FROM items WHERE sku = ?";

    private static final String INSERT_ROW =
            "INSERT OR IGNORE INTO items (sku, title, price, quantity, category)"
            + " VALUES (?, ?, ?, ?, ?)";

    private static final String DELETE_ROW = "DELETE FROM items WHERE sku = ?";

    private final Connection connection;
    private final PreparedStatement selectAll;
    private final PreparedStatement selectByCategory;
    private final PreparedStatement selectBySku;
    private final PreparedStatement insertRow;
    private final PreparedStatement deleteRow;

    public SqliteItemRepository(Connection connection) throws SQLException {
        this.connection = connection;
        try (Statement st = connection.createStatement()) {
            st.execute(CREATE_TABLE);
        }
        selectAll = connection.prepareStatement(SELECT_ALL);
        selectByCategory = connection.prepareStatement(SELECT_BY_CATEGORY);
        selectBySku = connection.prepareStatement(SELECT_BY_SKU);
        insertRow = connection.prepareStatement(INSERT_ROW);
        deleteRow = connection.prepareStatement(DELETE_ROW);
    }

    @Override
    public List<Item> findAll() {
        try (ResultSet rs = selectAll.executeQuery()) {
            return readItems(rs);
        } catch (SQLException e) {
            throw new IllegalStateException("failed to query items", e);
        }
    }

    @Override
    public List<Item> findByCategory(String category) {
        try {
            selectByCategory.setString(1, category);
            try (ResultSet rs = selectByCategory.executeQuery()) {
                return readItems(rs);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("failed to query items by category", e);
        }
    }

    @Override
    public Optional<Item> findBySku(String sku) {
        try {
            selectBySku.setString(1, sku);
            try (ResultSet rs = selectBySku.executeQuery()) {
                List<Item> rows = readItems(rs);
                return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("failed to query item by sku", e);
        }
    }

    @Override
    public boolean insert(Item item) {
        try {
            insertRow.setString(1, item.sku());
            insertRow.setString(2, item.title());
            insertRow.setDouble(3, item.price());
            insertRow.setInt(4, item.quantity());
            insertRow.setString(5, item.category());
            // INSERT OR IGNORE reports 1 when the row was stored and 0 when a
            // row with the same sku already existed.  This keeps the duplicate
            // check inside the storage layer, so concurrent inserts cannot
            // slip through a read-then-write window.
            return insertRow.executeUpdate() == 1;
        } catch (SQLException e) {
            throw new IllegalStateException("failed to insert item " + item.sku(), e);
        }
    }

    @Override
    public boolean delete(String sku) {
        try {
            deleteRow.setString(1, sku);
            return deleteRow.executeUpdate() > 0;
        } catch (SQLException e) {
            throw new IllegalStateException("failed to delete item " + sku, e);
        }
    }

    private static List<Item> readItems(ResultSet rs) throws SQLException {
        List<Item> rows = new ArrayList<>();
        while (rs.next()) {
            rows.add(new Item(
                    rs.getString(1),
                    rs.getString(2),
                    rs.getDouble(3),
                    rs.getInt(4),
                    rs.getString(5)));
        }
        return rows;
    }
}