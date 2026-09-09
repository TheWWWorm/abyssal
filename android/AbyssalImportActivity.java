package org.abyssal.engine;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.webkit.*;
import android.util.Base64;
import android.widget.*;
import android.view.ViewGroup;
import java.io.*;
import java.util.*;

/** A disposable importer process keeps WebView's native runtime separate from Godot. */
public final class AbyssalImportActivity extends Activity {
    private static final int LIMIT = 128 * 1024 * 1024;
    private static final String ORIGIN = "https://abyssal.invalid/";
    private WebView view;
    private volatile int generation = 1;
    private File input, output;
    private FileOutputStream stream;
    private long written;
    private TextView status;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(40, 40, 40, 40);
        layout.setBackgroundColor(0xff071b29);
        status = new TextView(this); status.setTextColor(0xffd6e8ee); status.setTextSize(22);
        status.setText("Preparing your DEEP content…");
        layout.addView(status, new LinearLayout.LayoutParams(-1, 0, 1));
        Button cancel = new Button(this); cancel.setText("Cancel import");
        cancel.setOnClickListener(v -> finish(1, "failed", "Import cancelled."));
        layout.addView(cancel); setContentView(layout);
        try {
            input = new File(getIntent().getStringExtra("input"));
            if (!input.getCanonicalFile().getParentFile().equals(getCacheDir().getCanonicalFile())
                    || !input.getName().startsWith("abyssal-input-")) throw new IOException("Invalid import path");
            startConverter(1);
        } catch (Exception e) { finish(1, "failed", e.getMessage()); }
    }
    private void report(String message) { runOnUiThread(() -> status.setText(message)); }
    private void startConverter(int token) {
        if (token != generation) return;
        try {
            report("Starting the offline importer…");
            view = new WebView(AbyssalImportActivity.this);
            view.setWebChromeClient(new android.webkit.WebChromeClient() {
                @Override public boolean onConsoleMessage(android.webkit.ConsoleMessage message) {
                    android.util.Log.i("AbyssalImporter", message.message()); return true;
                }
            });
            view.getSettings().setJavaScriptEnabled(true);
            view.getSettings().setAllowFileAccess(false);
            view.getSettings().setAllowContentAccess(false);
            view.getSettings().setBlockNetworkLoads(true);
            view.addJavascriptInterface(new Bridge(token), "AbyssalNative");
            view.setWebViewClient(new WebViewClient() {
                @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { return true; }
                @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                    String url = r.getUrl().toString();
                    try {
                        android.util.Log.d("AbyssalImporter", "Loading bundled importer resource: " + r.getUrl().getPath());
                        if (token != generation || !url.startsWith(ORIGIN)) throw new IOException("Blocked URL");
                        String path = url.substring(ORIGIN.length());
                        if (path.contains("..") || path.contains("%") || path.contains("?")) throw new IOException("Invalid asset");
                        InputStream bytes = path.equals("game.jar") ? new FileInputStream(input)
                            : AbyssalImportActivity.this.getAssets().open("abyssal-importer/" + path);
                        String mime = path.endsWith(".js") ? "text/javascript" : path.endsWith(".wasm")
                            ? "application/wasm" : path.endsWith(".html") ? "text/html" : "application/octet-stream";
                        return new WebResourceResponse(mime, "UTF-8", bytes);
                    } catch (Exception e) {
                        return new WebResourceResponse("text/plain", "UTF-8", 404, "Not found", Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
                    }
                }
                @Override public void onReceivedError(WebView v, WebResourceRequest r, android.webkit.WebResourceError e) {
                    if (r.isForMainFrame()) finish(token, "failed", "Android System WebView could not start the offline importer: " + e.getDescription());
                }
                @Override public boolean onRenderProcessGone(WebView v, android.webkit.RenderProcessGoneDetail detail) {
                    finish(token, "failed", "Android System WebView stopped. Update WebView, close other apps and try again."); return true;
                }
            });
            view.loadUrl(ORIGIN + "index.html");
        } catch (Exception e) { finish(token, "failed", "Android System WebView is required: " + e.getMessage()); }
    }
    private final class Bridge {
        private final int token;
        Bridge(int token) { this.token = token; }
        @JavascriptInterface public void progress(String message) {
            if (token == generation) { android.util.Log.i("AbyssalImporter", message); report(message); }
        }
        @JavascriptInterface public synchronized void begin() throws IOException {
            if (token != generation) return;
            if (stream != null) throw new IOException("Output already open");
            output = File.createTempFile("abyssal-import-", ".abyss", AbyssalImportActivity.this.getCacheDir());
            stream = new FileOutputStream(output); written = 0;
        }
        @JavascriptInterface public synchronized void chunk(String base64) throws IOException {
            if (token != generation) return;
            if (stream == null || base64.length() > 400000) throw new IOException("Invalid output chunk");
            byte[] bytes = Base64.decode(base64, Base64.DEFAULT);
            written += bytes.length;
            if (written > LIMIT) throw new IOException("Converted content exceeds 128 MiB");
            stream.write(bytes);
        }
        @JavascriptInterface public synchronized void complete() throws IOException {
            if (token != generation) return;
            if (stream == null) throw new IOException("Missing output");
            stream.close(); stream = null;
            String path = output.getAbsolutePath(); output = null;
            finish(token, "selected", path);
        }
        @JavascriptInterface public void failed(String message) { finish(token, "failed", message); }
    }

    private void finish(int token, String signal, String message) {
        runOnUiThread(() -> {
            if (token != generation) return;
            generation++;
            Intent result = new Intent(); result.putExtra(signal, message);
            setResult(RESULT_OK, result); finish();
        });
    }
    @Override public void onBackPressed() { finish(generation, "failed", "Import cancelled."); }
    @Override public void onDestroy() {
        generation++;
        if (view != null) { view.stopLoading(); view.destroy(); view = null; }
        try { if (stream != null) stream.close(); } catch (IOException ignored) {}
        if (output != null) output.delete();
        super.onDestroy();
    }
}
