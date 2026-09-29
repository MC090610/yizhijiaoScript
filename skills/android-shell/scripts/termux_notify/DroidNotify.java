/*
 * DroidNotify - post / update / cancel a status notification as the terminal app.
 *
 * It is launched through app_process (see scripts/droid.sh), so the process runs
 * with the terminal app's uid and the notification is attributed to that app
 * instead of com.android.shell.
 *
 * The host package is detected from the process uid, so the same helper works on
 * any device/terminal (Termux, ZeroTermux, ...). Override with DROID_NOTIFY_PKG.
 *
 *   app_process -Xnoimage-dex2oat / DroidNotify post  "标题" "正文"
 *   app_process -Xnoimage-dex2oat / DroidNotify post --alert "标题" "正文"
 *   app_process -Xnoimage-dex2oat / DroidNotify post --focus "标题" "正文"
 *   app_process -Xnoimage-dex2oat / DroidNotify cancel
 *   app_process -Xnoimage-dex2oat / DroidNotify dump-api
 *
 * Written with reflection only, so it compiles with plain javac and needs no
 * android.jar on the build machine.
 */
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class DroidNotify {

    /** Fallback when the uid lookup fails (standard Termux / ZeroTermux id). */
    private static final String DEFAULT_PKG = "com.termux";
    private static final String DEFAULT_ACTIVITY = "com.termux.app.TermuxActivity";

    private static final String CHANNEL_WORK = "droid_status";
    private static final String CHANNEL_DONE = "droid_done";
    private static final String CHANNEL_WORK_NAME = "Codex \u8fdb\u884c\u4e2d";
    private static final String CHANNEL_DONE_NAME = "Codex \u5df2\u5b8c\u6210";

    private static final int DEFAULT_NOTIFICATION_ID = 4211;
    private static final int IMPORTANCE_LOW = 2;
    private static final int IMPORTANCE_DEFAULT = 3;

    private static final int FLAG_ACTIVITY_NEW_TASK = 0x10000000;
    private static final int FLAG_IMMUTABLE = 0x04000000;
    private static final int FLAG_UPDATE_CURRENT = 0x08000000;

    public static void main(String[] args) {
        try {
            run(args);
        } catch (Throwable t) {
            System.err.println("droid-notify: " + t);
            t.printStackTrace(System.err);
            System.exit(2);
        }
        System.exit(0);
    }

    private static void run(String[] args) throws Exception {
        int i = 0;
        String cmd = args.length > 0 ? args[i++] : "help";
        boolean focus = false;
        boolean alert = false;
        while (i < args.length && args[i].startsWith("--")) {
            if ("--focus".equals(args[i])) focus = true;
            else if ("--alert".equals(args[i])) alert = true;
            i++;
        }
        String title = i < args.length ? args[i++] : null;
        String text = i < args.length ? args[i] : null;
        if (text == null) text = "";

        if ("dump-api".equals(cmd)) {
            dumpApi();
            return;
        }

        Object systemContext = systemContext();
        String pkg = detectPackage(systemContext);
        int id = notificationId();
        Object nm = notificationService();

        if ("cancel".equals(cmd)) {
            cancelNotification(nm, pkg, id);
            System.out.println("cancelled " + id + " for " + pkg);
            return;
        }
        if (!"post".equals(cmd)) {
            System.err.println("usage: DroidNotify post [--alert] [--focus] <title> <text>"
                    + " | cancel | dump-api");
            System.exit(1);
        }
        if (title == null || title.isEmpty()) title = "Codex";

        Object ctx = call("android.content.Context", systemContext, "createPackageContext",
                new String[]{"java.lang.String", "int"}, pkg, 0);
        Object manager = call("android.content.Context", ctx, "getSystemService",
                new String[]{"java.lang.String"}, "notification");

        if (System.getenv("DROID_NOTIFY_DEBUG") != null) {
            System.err.println("pkg = " + pkg
                    + ", ctx package = "
                    + call("android.content.Context", ctx, "getPackageName", new String[]{})
                    + ", opPackage = "
                    + call("android.content.Context", ctx, "getOpPackageName", new String[]{}));
        }

        String channelId = channelId(alert);
        ensureChannel(manager, channelId, channelName(alert), importance(alert));
        Object notification = buildNotification(ctx, pkg, channelId, title, text, focus);
        if (System.getenv("DROID_NOTIFY_DEBUG") != null) {
            System.err.println("notify target: " + notification);
        }
        enqueue(nm, pkg, notification, id);
        System.out.println("posted " + id + " for " + pkg);

        String hold = System.getenv("DROID_NOTIFY_HOLD");
        if (hold != null) {
            try {
                Thread.sleep(Long.parseLong(hold) * 1000L);
            } catch (InterruptedException ignored) {
            }
        }
    }

    private static int importance(boolean alert) {
        String v = System.getenv("DROID_NOTIFY_IMPORTANCE");
        if (v != null && !v.isEmpty()) {
            try {
                return Integer.parseInt(v);
            } catch (NumberFormatException ignored) {
            }
        }
        return alert ? IMPORTANCE_DEFAULT : IMPORTANCE_LOW;
    }

    /** Lets a second notification (e.g. a message to the user) coexist. */
    private static int notificationId() {
        String v = System.getenv("DROID_NOTIFY_ID");
        if (v != null && !v.isEmpty()) {
            try {
                return Integer.parseInt(v);
            } catch (NumberFormatException ignored) {
            }
        }
        return DEFAULT_NOTIFICATION_ID;
    }

    private static String channelId(boolean alert) {
        String v = System.getenv("DROID_NOTIFY_CHANNEL");
        if (v != null && !v.isEmpty()) return v;
        return alert ? CHANNEL_DONE : CHANNEL_WORK;
    }

    private static String channelName(boolean alert) {
        return alert ? CHANNEL_DONE_NAME : CHANNEL_WORK_NAME;
    }

    /** The terminal app's package name, derived from the process uid. */
    private static String detectPackage(Object systemContext) {
        String override = System.getenv("DROID_NOTIFY_PKG");
        if (override != null && !override.isEmpty()) return override;
        try {
            Object uid = Class.forName("android.os.Process").getMethod("myUid").invoke(null);
            Object pm = call("android.content.Context", systemContext, "getPackageManager",
                    new String[]{});
            Object packages = call("android.content.pm.PackageManager", pm,
                    "getPackagesForUid", new String[]{"int"}, uid);
            if (packages instanceof String[] && ((String[]) packages).length > 0) {
                return ((String[]) packages)[0];
            }
        } catch (Throwable ignored) {
        }
        return DEFAULT_PKG;
    }

    /** A system Context with a prepared Looper (no running app required). */
    private static Object systemContext() throws Exception {
        // ActivityThread.systemMain() builds a Handler, so the main Looper must
        // exist first (same thing termux-am's app_process entry point does).
        Class<?> looper = Class.forName("android.os.Looper");
        if (looper.getMethod("getMainLooper").invoke(null) == null) {
            looper.getMethod("prepareMainLooper").invoke(null);
        }
        Class<?> activityThread = Class.forName("android.app.ActivityThread");
        Object thread = activityThread.getMethod("systemMain").invoke(null);
        return activityThread.getMethod("getSystemContext").invoke(thread);
    }

    /*
     * A NotificationManager obtained from createPackageContext() still reports
     * getOpPackageName() == "android", and MIUI refuses the post with
     * "Permission Denied to post local notification for android". So talk to
     * INotificationManager directly and pass the host package for both pkg and
     * opPkg.
     */
    private static Object notificationService() throws Exception {
        Object binder = Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "notification");
        return Class.forName("android.app.INotificationManager$Stub")
                .getMethod("asInterface", Class.forName("android.os.IBinder"))
                .invoke(null, binder);
    }

    private static Method ifaceMethod(String name, int paramCount, String mustUseType)
            throws Exception {
        for (Method m : Class.forName("android.app.INotificationManager").getMethods()) {
            if (!m.getName().equals(name) || m.getParameterCount() != paramCount) continue;
            if (mustUseType != null) {
                boolean found = false;
                for (Class<?> p : m.getParameterTypes()) {
                    if (p.getName().equals(mustUseType)) found = true;
                }
                if (!found) continue;
            }
            return m;
        }
        throw new NoSuchMethodException(name + "/" + paramCount + " on INotificationManager");
    }

    private static void dumpApi() throws Exception {
        for (Method m : Class.forName("android.app.INotificationManager").getMethods()) {
            String n = m.getName();
            if (!(n.contains("Channel") || n.contains("enqueueNotification")
                    || n.contains("cancelNotification"))) continue;
            StringBuilder sb = new StringBuilder(n).append('(');
            Class<?>[] ps = m.getParameterTypes();
            for (int k = 0; k < ps.length; k++) {
                if (k > 0) sb.append(", ");
                sb.append(ps[k].getSimpleName());
            }
            System.out.println(sb.append(')').toString());
        }
    }

    private static void ensureChannel(Object nm, String channelId, String channelName,
                                      int importance) throws Exception {
        // Channel creation uses the Context's package name, which is correct, so
        // the plain NotificationManager is fine here.
        Object channel = newInstance("android.app.NotificationChannel",
                new String[]{"java.lang.String", "java.lang.CharSequence", "int"},
                channelId, channelName, importance);
        call("android.app.NotificationChannel", channel, "setShowBadge",
                new String[]{"boolean"}, false);
        call("android.app.NotificationManager", nm, "createNotificationChannel",
                new String[]{"android.app.NotificationChannel"}, channel);
    }

    private static void enqueue(Object nm, String pkg, Object notification, int id)
            throws Exception {
        ifaceMethod("enqueueNotificationWithTag", 6, "android.app.Notification")
                .invoke(nm, pkg, pkg, null, id, notification, 0);
    }

    private static void cancelNotification(Object nm, String pkg, int id) throws Exception {
        try {
            ifaceMethod("cancelNotificationWithTag", 5, null)
                    .invoke(nm, pkg, pkg, null, id, 0);
        } catch (NoSuchMethodException e) {
            ifaceMethod("cancelNotificationWithTag", 4, null)
                    .invoke(nm, pkg, null, id, 0);
        }
    }

    private static Object buildNotification(Object ctx, String pkg, String channelId,
                                            String title, String text, boolean focus)
            throws Exception {
        Object builder = newInstance("android.app.Notification$Builder",
                new String[]{"android.content.Context", "java.lang.String"},
                ctx, channelId);

        call("android.app.Notification$Builder", builder, "setSmallIcon",
                new String[]{"int"}, appIconRes(ctx));
        call("android.app.Notification$Builder", builder, "setContentTitle",
                new String[]{"java.lang.CharSequence"}, title);
        call("android.app.Notification$Builder", builder, "setContentText",
                new String[]{"java.lang.CharSequence"}, text);
        call("android.app.Notification$Builder", builder, "setOnlyAlertOnce",
                new String[]{"boolean"}, true);
        call("android.app.Notification$Builder", builder, "setContentIntent",
                new String[]{"android.app.PendingIntent"}, contentIntent(ctx, pkg));

        Object style = newInstance("android.app.Notification$BigTextStyle",
                new String[]{}, new Object[]{});
        call("android.app.Notification$BigTextStyle", style, "bigText",
                new String[]{"java.lang.CharSequence"}, text);
        call("android.app.Notification$Builder", builder, "setStyle",
                new String[]{"android.app.Notification$Style"}, style);

        if (focus) {
            Object params = newInstance("android.os.Bundle", new String[]{}, new Object[]{});
            put(params, "miui.focus.paramType", "focus");
            put(params, "miui.focus.title", title);
            put(params, "miui.focus.contentText", text);
            put(params, "miui.focus.ticker", text);
            Object extras = newInstance("android.os.Bundle", new String[]{}, new Object[]{});
            call("android.os.Bundle", extras, "putBundle",
                    new String[]{"java.lang.String", "android.os.Bundle"},
                    "miui.focus.param", params);
            call("android.app.Notification$Builder", builder, "addExtras",
                    new String[]{"android.os.Bundle"}, extras);
        }

        return call("android.app.Notification$Builder", builder, "build", new String[]{});
    }

    private static void put(Object bundle, String key, String value) throws Exception {
        call("android.os.Bundle", bundle, "putString",
                new String[]{"java.lang.String", "java.lang.String"}, key, value);
    }

    /** Tap on the notification opens whatever launches the terminal app. */
    private static Object contentIntent(Object ctx, String pkg) throws Exception {
        Object pm = call("android.content.Context", ctx, "getPackageManager", new String[]{});
        Object launch = call("android.content.pm.PackageManager", pm,
                "getLaunchIntentForPackage", new String[]{"java.lang.String"}, pkg);
        Object intent;
        if (launch != null) {
            intent = launch;
        } else {
            intent = newInstance("android.content.Intent", new String[]{}, new Object[]{});
            call("android.content.Intent", intent, "setClassName",
                    new String[]{"java.lang.String", "java.lang.String"},
                    pkg, DEFAULT_ACTIVITY);
        }
        call("android.content.Intent", intent, "addFlags",
                new String[]{"int"}, FLAG_ACTIVITY_NEW_TASK);
        return call("android.app.PendingIntent", null, "getActivity",
                new String[]{"android.content.Context", "int",
                        "android.content.Intent", "int"},
                ctx, 0, intent, FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT);
    }

    private static int appIconRes(Object ctx) throws Exception {
        Object appInfo = call("android.content.Context", ctx, "getApplicationInfo",
                new String[]{});
        Field icon = Class.forName("android.content.pm.ApplicationInfo").getField("icon");
        return icon.getInt(appInfo);
    }

    // --- tiny reflection helpers -------------------------------------------

    private static Class<?> type(String name) throws ClassNotFoundException {
        if ("int".equals(name)) return int.class;
        if ("boolean".equals(name)) return boolean.class;
        return Class.forName(name);
    }

    private static Object call(String owner, Object target, String name,
                               String[] paramNames, Object... args) throws Exception {
        Class<?>[] types = new Class<?>[paramNames.length];
        for (int i = 0; i < types.length; i++) types[i] = type(paramNames[i]);
        Method m = Class.forName(owner).getMethod(name, types);
        return m.invoke(target, args);
    }

    private static Object newInstance(String owner, String[] paramNames, Object... args)
            throws Exception {
        Class<?>[] types = new Class<?>[paramNames.length];
        for (int i = 0; i < types.length; i++) types[i] = type(paramNames[i]);
        return Class.forName(owner).getConstructor(types).newInstance(args);
    }
}
