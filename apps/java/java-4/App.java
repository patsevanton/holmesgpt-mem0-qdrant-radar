import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.List;

public class App {
    static final List<byte[]> kept = new ArrayList<>();

    public static void main(String[] args) throws IOException {
        String raw = System.getenv("LISTEN_PORT");
        int port = raw == null || raw.isEmpty() ? 8080 : Integer.parseInt(raw);
        int chunk = Integer.parseInt(System.getenv().getOrDefault("CHUNK_KB", "256"));
        Thread loader = new Thread(() -> {
            while (true) {
                kept.add(new byte[chunk * 1024]);
                try {
                    Thread.sleep(200);
                } catch (InterruptedException e) {
                    return;
                }
            }
        });
        loader.setDaemon(true);
        loader.start();
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);
        server.createContext("/", exchange -> {
            byte[] body = "ok".getBytes();
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });
        server.start();
    }
}
