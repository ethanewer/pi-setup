package catalog;

import catalog.db.SqliteItemRepository;
import catalog.http.ApiServer;
import catalog.json.JsonCodec;
import catalog.service.CatalogService;

import java.sql.Connection;
import java.sql.DriverManager;

/**
 * Entry point of the catalogue service.
 *
 * Wiring is done here, by hand: connect to the SQLite file, build the
 * repository, inject it (together with the JSON codec) into the service,
 * and hand the service to the HTTP server.  Nothing reads configuration
 * from anywhere else; the two command-line arguments are the whole
 * configuration surface.
 */
public final class Main {

    private Main() {
    }

    public static void main(String[] args) {
        if (args.length != 2) {
            System.err.println("usage: catalog.Main <sqlite-db-path> <port>");
            System.exit(2);
            return;
        }
        String dbPath = args[0];
        int port;
        try {
            port = Integer.parseInt(args[1]);
        } catch (NumberFormatException e) {
            System.err.println("bad port: " + args[1]);
            System.exit(2);
            return;
        }

        try {
            Class.forName("org.sqlite.JDBC");
            String url = "jdbc:sqlite:" + dbPath;
            Connection connection = DriverManager.getConnection(url);

            SqliteItemRepository repository = new SqliteItemRepository(connection);
            JsonCodec json = new JsonCodec();
            CatalogService service = new CatalogService(repository, json);
            ApiServer server = new ApiServer(service, json, port);

            server.start();
            System.err.println("catalog service listening on 127.0.0.1:" + server.boundPort());

            // The HttpServer executor runs on a non-daemon thread, so the JVM
            // stays alive after main returns; the launcher owns this process
            // and terminates it with SIGTERM, at which point the connection
            // and the server shut down together.
        } catch (Exception e) {
            System.err.println("fatal: " + e);
            System.exit(1);
        }
    }
}