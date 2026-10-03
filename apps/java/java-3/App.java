import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.concurrent.Executors;

public class App {
    public static void main(String[] args) throws IOException {
        String raw = System.getenv("LISTEN_PORT");
        int port = raw == null || raw.isEmpty() ? 8080 : Integer.parseInt(raw);
        int workers = Integer.parseInt(System.getenv().getOrDefault("WORKER_THREADS", "4"));
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);
        server.setExecutor(Executors.newFixedThreadPool(workers));
        server.createContext("/", exchange -> {
            try {
                Thread.sleep(120_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            byte[] body = "ok".getBytes();
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });
        server.start();
    }
}
