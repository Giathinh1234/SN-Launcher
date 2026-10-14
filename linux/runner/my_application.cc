#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <cstdio>
#include <cstring>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // Parsed from the command line before activate(). Kiosk mode is what a Nest
  // Hub replacement actually runs as on a Raspberry Pi panel or a stripped-down
  // image: no title bar, no decorations, no window manager furniture.
  gboolean kiosk = FALSE;
  int forced_width = 0;
  int forced_height = 0;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_widget_show(GTK_WIDGET(window));
  if (self->kiosk) {
    gtk_window_fullscreen(window);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  if (self->kiosk) {
    // The panel *is* the UI: no header bar, no close button, no resize grips.
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_title(window, "Nest Launcher");
  } else {
    // Use a header bar when running in GNOME as this is the common style used
    // by applications and is the setup most users will be using (e.g. Ubuntu
    // desktop).
    // If running on X and not using GNOME then just use a traditional title bar
    // in case the window manager does more exotic layout, e.g. tiling.
    // If running on Wayland assume the header bar will work (may need changing
    // if future cases occur).
    gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
    GdkScreen* screen = gtk_window_get_screen(window);
    if (GDK_IS_X11_SCREEN(screen)) {
      const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
      if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
        use_header_bar = FALSE;
      }
    }
#endif
    if (use_header_bar) {
      GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
      gtk_widget_show(GTK_WIDGET(header_bar));
      gtk_header_bar_set_title(header_bar, "Nest Launcher");
      gtk_header_bar_set_show_close_button(header_bar, TRUE);
      gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    } else {
      gtk_window_set_title(window, "Nest Launcher");
    }

    if (self->forced_width > 0 && self->forced_height > 0) {
      gtk_window_set_default_size(window, self->forced_width,
                                  self->forced_height);
      gtk_widget_set_size_request(GTK_WIDGET(window), self->forced_width,
                                  self->forced_height);
    } else {
      gtk_window_set_default_size(window, 1280, 720);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);

  // Strip out the first argument as it is the binary name, and pick off the
  // runner's own flags so they never reach the Dart entrypoint.
  //   --kiosk              undecorated, fullscreen
  //   --size=1024x600      force an exact window size (matches a real panel)
  gchar** forwarded = g_new0(gchar*, g_strv_length(*arguments) + 1);
  int out = 0;
  for (gchar** arg = *arguments + 1; *arg != nullptr; ++arg) {
    if (g_strcmp0(*arg, "--kiosk") == 0) {
      self->kiosk = TRUE;
    } else if (g_str_has_prefix(*arg, "--size=")) {
      const gchar* spec = *arg + strlen("--size=");
      gint w = 0, h = 0;
      if (sscanf(spec, "%dx%d", &w, &h) == 2 && w > 0 && h > 0) {
        self->forced_width = w;
        self->forced_height = h;
      }
    } else {
      forwarded[out++] = *arg;
    }
  }
  self->dart_entrypoint_arguments = forwarded;

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
