package io.github.guandor.balatrolite;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Small host-JVM smoke test used against a locally owned Balatro.exe. */
public final class BalatroPatcherSmokeTest {
    private BalatroPatcherSmokeTest() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 7) {
            throw new IllegalArgumentException(
                "Expected: Balatro.exe small_screen.lua options.lua controls.lua perf.lua " +
                "Nunito-Black.ttf output-directory"
            );
        }

        File outputDirectory = new File(args[6]);
        if (!outputDirectory.isDirectory() && !outputDirectory.mkdirs()) {
            throw new IllegalStateException("Could not create test output directory");
        }
        File source = new File(outputDirectory, "source.love");
        File patched = new File(outputDirectory, "patched.love");
        File original = new File(outputDirectory, "patched-original.love");
        File smallStock = new File(outputDirectory, "patched-small-stock.love");
        File originalOptimized = new File(outputDirectory, "patched-original-optimized.love");
        byte[] smallScreen = Files.readAllBytes(new File(args[1]).toPath());
        byte[] options = Files.readAllBytes(new File(args[2]).toPath());
        byte[] device = Files.readAllBytes(new File(args[3]).toPath());
        byte[] performance = Files.readAllBytes(new File(args[4]).toPath());
        byte[] font = Files.readAllBytes(new File(args[5]).toPath());

        BalatroPatcher.normalizeGameArchive(new File(args[0]), source);
        BalatroPatcher.patchGame(
            source,
            patched,
            smallScreen,
            options,
            device,
            performance,
            font,
            true,
            true,
            System.out::println
        );

        try (ZipFile archive = new ZipFile(patched)) {
            require(archive.getEntry("portmaster/small_screen.lua") != null, "layout missing");
            require(archive.getEntry("portmaster/options.lua") != null, "options missing");
            require(archive.getEntry("portmaster/controls.lua") != null, "device patch missing");
            require(archive.getEntry("portmaster/pm_android_config.lua") != null,
                "Android settings missing");
            require(archive.getEntry("portmaster/perf.lua") != null, "performance patch missing");
            require(archive.getEntry("resources/fonts/m6x11plus.ttf") != null, "font missing");
            require(read(archive, "globals.lua").contains("crt = 0,"),
                "performance-on defaults missing");
            require(read(archive, "main.lua").contains("G.FPS_CAP = G.FPS_CAP or 500"),
                "main.lua should leave the frame cap to perf.lua");
            require(read(archive, "conf.lua").contains("t.externalstorage = true"),
                "Android external save storage is not enabled");
        }

        BalatroPatcher.patchGame(
            source,
            original,
            smallScreen,
            options,
            device,
            performance,
            font,
            false,
            false,
            System.out::println
        );
        try (ZipFile archive = new ZipFile(original)) {
            require(archive.getEntry("portmaster/small_screen.lua") == null,
                "original layout unexpectedly contains the small-screen module");
            require(read(archive, "portmaster/pm_android_config.lua").contains("false"),
                "performance-off setting missing");
            require(!read(archive, "main.lua").contains("portmaster/small_screen"),
                "original layout unexpectedly requires the small-screen module");
            require(read(archive, "resources/shaders/background.fs").contains("i < 5; i++"),
                "performance-off build unexpectedly trimmed the background shader");
            require(read(archive, "globals.lua").contains("crt = 70,"),
                "performance-off build unexpectedly changed graphics defaults");
            require(read(archive, "main.lua").contains("G.FPS_CAP = G.FPS_CAP or 500"),
                "performance-off build unexpectedly forced a frame cap");
        }

        BalatroPatcher.patchGame(
            source, smallStock, smallScreen, options, device, performance, font,
            true, false, System.out::println
        );
        try (ZipFile archive = new ZipFile(smallStock)) {
            require(archive.getEntry("portmaster/small_screen.lua") != null,
                "small/performance-off layout missing");
            require(read(archive, "portmaster/pm_android_config.lua").contains("false"),
                "small/performance-off setting missing");
            require(read(archive, "globals.lua").contains("crt = 70,"),
                "small layout incorrectly enabled performance defaults");
            require(read(archive, "globals.lua").contains("self.F_HIDE_BG = false"),
                "small layout incorrectly forced background hiding");
            require(read(archive, "resources/shaders/background.fs").contains("i < 5; i++"),
                "small/performance-off build unexpectedly trimmed the shader");
        }

        BalatroPatcher.patchGame(
            source, originalOptimized, smallScreen, options, device, performance, font,
            false, true, System.out::println
        );
        try (ZipFile archive = new ZipFile(originalOptimized)) {
            require(archive.getEntry("portmaster/small_screen.lua") == null,
                "original/performance-on build contains the small-screen module");
            require(read(archive, "portmaster/pm_android_config.lua").contains("true"),
                "original/performance-on setting missing");
            require(read(archive, "globals.lua").contains("crt = 0,"),
                "original/performance-on defaults missing");
            require(read(archive, "resources/shaders/background.fs").contains("i < 2; i++"),
                "original/performance-on build did not trim the shader");
        }
        System.out.println(
            "All four layout/performance combinations verified."
        );
    }

    private static String read(ZipFile archive, String name) throws Exception {
        ZipEntry entry = archive.getEntry(name);
        require(entry != null, name + " missing");
        return new String(archive.getInputStream(entry).readAllBytes(), StandardCharsets.UTF_8);
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
