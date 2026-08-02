package io.github.guandor.balatrolite;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/** Host-JVM checks for the one-time internal-to-external save migration. */
public final class SaveMigratorSmokeTest {
    private SaveMigratorSmokeTest() {}

    public static void main(String[] args) throws Exception {
        File root = Files.createTempDirectory("balatro-save-migration-").toFile();
        try {
            File internal = new File(root, "internal");
            File external = new File(root, "external");
            File profile = new File(internal, "1/profile.jkr");
            require(profile.getParentFile().mkdirs(), "could not create test input");
            Files.writeString(profile.toPath(), "internal", StandardCharsets.UTF_8);

            SaveMigrator.copyMissing(internal, external);
            File migrated = new File(external, "1/profile.jkr");
            require(migrated.isFile(), "nested save was not migrated");
            require(Files.readString(migrated.toPath()).equals("internal"),
                "migrated save contents changed");

            Files.writeString(migrated.toPath(), "external", StandardCharsets.UTF_8);
            SaveMigrator.copyMissing(internal, external);
            require(Files.readString(migrated.toPath()).equals("external"),
                "an existing external save was overwritten");

            System.out.println("Save migration verified.");
        } finally {
            deleteTree(root);
        }
    }

    private static void deleteTree(File file) throws Exception {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteTree(child);
                }
            }
        }
        Files.deleteIfExists(file.toPath());
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
