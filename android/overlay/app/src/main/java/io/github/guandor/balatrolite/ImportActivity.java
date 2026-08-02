package io.github.guandor.balatrolite;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.core.content.FileProvider;

import org.love2d.android.GameActivity;
import org.love2d.android.executable.BuildConfig;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** First-run importer. The APK contains no Balatro game data. */
public final class ImportActivity extends Activity {
    private static final int PICK_GAME_FILE = 10;
    private static final String PREFS = "balatro_lite_import";
    private static final String PREF_PATCH_VERSION = "patch_version";
    private static final String PREF_PATCH_SCHEMA = "patch_schema";
    private static final String PREF_SETUP_DONE = "setup_done";
    private static final String PREF_SMALL_LAYOUT = "small_layout";
    private static final String PREF_PERFORMANCE = "performance_optimizations";
    // Increment whenever patch behavior changes without relying on the APK's
    // versionCode. Local debug builds intentionally keep versionCode 1.
    private static final int PATCH_SCHEMA_VERSION = 2;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextView status;
    private Button chooseButton;
    private ProgressBar progress;
    private RadioGroup layoutChoices;
    private RadioGroup performanceChoices;
    private File gameDirectory;
    private File sourceLove;
    private File patchedLove;
    private File setupRequest;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        gameDirectory = new File(getFilesDir(), "games");
        sourceLove = new File(gameDirectory, "source.love");
        patchedLove = new File(gameDirectory, "balatro-lite.love");
        setupRequest = new File(getFilesDir(),
            "save/balatro-lite/android-port-setup.request");

        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        int patchedVersion = preferences.getInt(PREF_PATCH_VERSION, -1);
        int patchSchema = preferences.getInt(PREF_PATCH_SCHEMA, -1);
        if (sourceLove.isFile() &&
            (!preferences.getBoolean(PREF_SETUP_DONE, false) || setupRequest.isFile())) {
            buildSetupInterface();
        } else if (patchedLove.isFile() && patchedVersion == BuildConfig.VERSION_CODE &&
            patchSchema == PATCH_SCHEMA_VERSION) {
            launchGame();
        } else if (sourceLove.isFile()) {
            buildImportInterface();
            setBusy("Updating the handheld patch…");
            worker.execute(() -> patchStoredGame(false));
        } else {
            buildImportInterface();
        }
    }

    private void buildImportInterface() {
        int padding = dp(28);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(padding, padding, padding, padding);
        root.setBackgroundColor(Color.rgb(24, 32, 46));

        TextView title = new TextView(this);
        title.setText("Balatro Lite");
        title.setTextColor(Color.rgb(246, 180, 54));
        title.setTextSize(32);
        title.setGravity(Gravity.CENTER);
        root.addView(title, matchWrap());

        TextView explanation = new TextView(this);
        explanation.setText(
            "Choose Balatro.exe from a copy you own. It is imported and patched " +
            "entirely on this device; the APK does not include the game."
        );
        explanation.setTextColor(Color.WHITE);
        explanation.setTextSize(17);
        explanation.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams explanationParams = matchWrap();
        explanationParams.topMargin = dp(14);
        explanationParams.bottomMargin = dp(22);
        explanationParams.width = dp(560);
        root.addView(explanation, explanationParams);

        chooseButton = new Button(this);
        chooseButton.setText("Choose Balatro.exe");
        chooseButton.setTextSize(17);
        chooseButton.setOnClickListener(view -> openFilePicker());
        LinearLayout.LayoutParams buttonParams = wrapWrap();
        buttonParams.width = dp(280);
        root.addView(chooseButton, buttonParams);

        progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        progress.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressParams = wrapWrap();
        progressParams.topMargin = dp(18);
        root.addView(progress, progressParams);

        status = new TextView(this);
        status.setText("Balatro 1.0.1o is currently supported. Balatro.love also works.");
        status.setTextColor(Color.rgb(190, 199, 214));
        status.setTextSize(14);
        status.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams statusParams = matchWrap();
        statusParams.topMargin = dp(12);
        root.addView(status, statusParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(root);
        setContentView(scroll);
    }

    private void buildSetupInterface() {
        int padding = dp(24);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(padding, padding, padding, padding);
        root.setBackgroundColor(Color.rgb(24, 32, 46));

        TextView title = setupText("Initialize Port Settings", 28, Color.rgb(246, 180, 54));
        root.addView(title, matchWrap());

        TextView layoutLabel = setupText("Screen layout", 18, Color.WHITE);
        LinearLayout.LayoutParams labelParams = matchWrap();
        labelParams.topMargin = dp(14);
        root.addView(layoutLabel, labelParams);

        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        layoutChoices = new RadioGroup(this);
        layoutChoices.setOrientation(RadioGroup.HORIZONTAL);
        layoutChoices.setGravity(Gravity.CENTER);
        RadioButton smallLayout = setupChoice("Small-screen layout", 1001);
        RadioButton originalLayout = setupChoice("Original layout", 1002);
        layoutChoices.addView(smallLayout);
        layoutChoices.addView(originalLayout);
        layoutChoices.check(preferences.getBoolean(PREF_SMALL_LAYOUT, true) ? 1001 : 1002);
        root.addView(layoutChoices, wrapWrap());

        TextView performanceLabel = setupText("Performance changes", 18, Color.WHITE);
        LinearLayout.LayoutParams performanceLabelParams = matchWrap();
        performanceLabelParams.topMargin = dp(10);
        root.addView(performanceLabel, performanceLabelParams);

        performanceChoices = new RadioGroup(this);
        performanceChoices.setOrientation(RadioGroup.HORIZONTAL);
        performanceChoices.setGravity(Gravity.CENTER);
        RadioButton optimized = setupChoice("On (recommended)", 2001);
        RadioButton stock = setupChoice("Off", 2002);
        performanceChoices.addView(optimized);
        performanceChoices.addView(stock);
        performanceChoices.check(preferences.getBoolean(PREF_PERFORMANCE, true) ? 2001 : 2002);
        root.addView(performanceChoices, wrapWrap());

        chooseButton = new Button(this);
        chooseButton.setText("Apply and Start Game");
        chooseButton.setTextSize(17);
        chooseButton.setOnClickListener(view -> saveSetupAndPatch());
        LinearLayout.LayoutParams buttonParams = wrapWrap();
        buttonParams.width = dp(280);
        buttonParams.topMargin = dp(14);
        root.addView(chooseButton, buttonParams);

        progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        progress.setVisibility(View.GONE);
        root.addView(progress, wrapWrap());

        status = setupText(
            "These choices rebuild only your private imported game.",
            14,
            Color.rgb(190, 199, 214)
        );
        LinearLayout.LayoutParams statusParams = matchWrap();
        statusParams.topMargin = dp(8);
        root.addView(status, statusParams);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(root);
        setContentView(scroll);
    }

    private TextView setupText(String value, int size, int colour) {
        TextView text = new TextView(this);
        text.setText(value);
        text.setTextColor(colour);
        text.setTextSize(size);
        text.setGravity(Gravity.CENTER);
        return text;
    }

    private RadioButton setupChoice(String label, int id) {
        RadioButton button = new RadioButton(this);
        button.setId(id);
        button.setText(label);
        button.setTextColor(Color.WHITE);
        button.setTextSize(16);
        return button;
    }

    private void saveSetupAndPatch() {
        boolean smallLayout = layoutChoices.getCheckedRadioButtonId() == 1001;
        boolean performanceOptimizations =
            performanceChoices.getCheckedRadioButtonId() == 2001;
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putBoolean(PREF_SETUP_DONE, true)
            .putBoolean(PREF_SMALL_LAYOUT, smallLayout)
            .putBoolean(PREF_PERFORMANCE, performanceOptimizations)
            .apply();
        BalatroPatcher.deleteQuietly(setupRequest);
        setBusy("Applying your port settings…");
        worker.execute(() -> patchStoredGame(false));
    }

    private void openFilePicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        // Providers disagree about the MIME type of Windows executables. Show
        // all documents and enforce the supported filename after selection.
        intent.setType("*/*");
        startActivityForResult(intent, PICK_GAME_FILE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK_GAME_FILE || resultCode != RESULT_OK || data == null ||
            data.getData() == null) {
            return;
        }

        Uri selected = data.getData();
        String name = displayName(selected);
        String lowerName = name.toLowerCase(Locale.ROOT);
        if (!lowerName.endsWith(".exe") && !lowerName.endsWith(".love")) {
            showError("Choose Balatro.exe or Balatro.love.");
            return;
        }

        setBusy("Copying " + name + "…");
        worker.execute(() -> importSelectedGame(selected));
    }

    private void importSelectedGame(Uri selected) {
        if (!gameDirectory.exists() && !gameDirectory.mkdirs()) {
            showError("Could not create the app's private game folder.");
            return;
        }

        File selectedCopy = new File(gameDirectory, ".selected.tmp");
        File sourceTemporary = new File(gameDirectory, ".source.tmp");
        BalatroPatcher.deleteQuietly(selectedCopy);
        BalatroPatcher.deleteQuietly(sourceTemporary);

        try (InputStream input = getContentResolver().openInputStream(selected);
             FileOutputStream output = new FileOutputStream(selectedCopy)) {
            if (input == null) {
                throw new IOException("The selected document could not be opened.");
            }
            copy(input, output);
            postStatus("Checking the game archive…");
            BalatroPatcher.normalizeGameArchive(selectedCopy, sourceTemporary);
            replaceFile(sourceTemporary, sourceLove);
            runOnUiThread(this::buildSetupInterface);
        } catch (Exception error) {
            showError(messageFor(error));
        } finally {
            BalatroPatcher.deleteQuietly(selectedCopy);
            BalatroPatcher.deleteQuietly(sourceTemporary);
        }
    }

    private void patchStoredGame(boolean freshImport) {
        try {
            postStatus(freshImport ? "Applying the handheld and Android patches…" :
                "Updating the handheld patch…");
            byte[] smallScreen = readAsset("patches/small_screen.lua");
            byte[] options = readAsset("patches/options.lua");
            byte[] controls = readAsset("patches/controls.lua");
            byte[] performance = readAsset("patches/perf.lua");
            byte[] font = readAsset("patches/Nunito-Black.ttf");
            SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
            boolean smallLayout = preferences.getBoolean(PREF_SMALL_LAYOUT, true);
            boolean performanceOptimizations = preferences.getBoolean(PREF_PERFORMANCE, true);
            BalatroPatcher.patchGame(
                sourceLove,
                patchedLove,
                smallScreen,
                options,
                controls,
                performance,
                font,
                smallLayout,
                performanceOptimizations,
                this::postStatus
            );
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putInt(PREF_PATCH_VERSION, BuildConfig.VERSION_CODE)
                .putInt(PREF_PATCH_SCHEMA, PATCH_SCHEMA_VERSION)
                .apply();
            runOnUiThread(this::launchGame);
        } catch (Exception error) {
            showError(messageFor(error));
        }
    }

    private void launchGame() {
        Uri game = FileProvider.getUriForFile(
            this,
            BuildConfig.APPLICATION_ID + ".files",
            patchedLove
        );
        Intent intent = new Intent(this, GameActivity.class);
        intent.setDataAndType(game, "application/octet-stream");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(intent);
        finish();
    }

    private byte[] readAsset(String name) throws IOException {
        try (InputStream input = getAssets().open(name);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            copy(input, output);
            return output.toByteArray();
        }
    }

    private void setBusy(String message) {
        chooseButton.setEnabled(false);
        progress.setVisibility(View.VISIBLE);
        status.setTextColor(Color.WHITE);
        status.setText(message);
    }

    private void postStatus(String message) {
        runOnUiThread(() -> status.setText(message));
    }

    private void showError(String message) {
        runOnUiThread(() -> {
            chooseButton.setEnabled(true);
            progress.setVisibility(View.GONE);
            status.setTextColor(Color.rgb(255, 112, 112));
            status.setText(message);
        });
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(
                 uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (column >= 0) {
                    String value = cursor.getString(column);
                    if (value != null) {
                        return value;
                    }
                }
            }
        } catch (RuntimeException ignored) {
            // Fall through to the URI path when a provider does not expose metadata.
        }
        String path = uri.getLastPathSegment();
        return path == null ? "Balatro.exe" : path;
    }

    private String messageFor(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ?
            "The game could not be imported." : message;
    }

    private static void replaceFile(File source, File destination) throws IOException {
        BalatroPatcher.deleteQuietly(destination);
        if (!source.renameTo(destination)) {
            throw new IOException("Could not store the imported game archive.");
        }
    }

    private static void copy(InputStream input, java.io.OutputStream output) throws IOException {
        byte[] buffer = new byte[64 * 1024];
        int count;
        while ((count = input.read(buffer)) >= 0) {
            output.write(buffer, 0, count);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    private static LinearLayout.LayoutParams wrapWrap() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    @Override
    protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
