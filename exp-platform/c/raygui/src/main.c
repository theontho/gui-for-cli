#include "app.h"
#include "args.h"
#include "bundle.h"
#include "ui.h"

#include "raylib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double elapsed_ms(struct timespec start, struct timespec end) {
  return (double)(end.tv_sec - start.tv_sec) * 1000.0 +
         (double)(end.tv_nsec - start.tv_nsec) / 1000000.0;
}

static void print_benchmark(const GfcApp* app, double loaded_ms, double ready_ms, double full_warm_ms) {
  printf(
      "gfc-raygui-c benchmark bundle_loaded_ms=%.1f ui_ready_ms=%.1f",
      loaded_ms,
      ready_ms
  );
  if (full_warm_ms >= 0.0) {
    printf(" full_feature_warm_ms=%.1f", full_warm_ms);
  }
  printf(
      " pages=%zu controls=%zu actions=%zu setup_steps=%zu data_sources=%zu "
      "data_sources_loaded=%zu terminal_text_direction=%s\n",
      app->bundle.page_count,
      app->bundle.control_count,
      app->bundle.action_count,
      app->bundle.setup_step_count,
      app->bundle.data_source_count,
      app->data_sources_loaded,
      app->bundle.terminal_text_direction
  );
  fflush(stdout);
}

static int run(int argc, char** argv) {
  struct timespec started;
  struct timespec loaded;
  clock_gettime(CLOCK_MONOTONIC, &started);

  GfcArgs args;
  char* error = NULL;
  if (!gfc_parse_args(argc, argv, &args, &error)) {
    fprintf(stderr, "gui-for-cli-raygui-c: %s\n", error);
    free(error);
    return 1;
  }
  if (args.version) {
    printf("gui-for-cli-raygui-c 0.1.0\n");
    gfc_args_free(&args);
    return 0;
  }

  GfcBundle bundle;
  if (!gfc_load_bundle(args.bundle, args.repo_root, args.locale, &bundle, &error)) {
    fprintf(stderr, "gui-for-cli-raygui-c: %s\n", error);
    free(error);
    gfc_args_free(&args);
    return 1;
  }
  clock_gettime(CLOCK_MONOTONIC, &loaded);

  GfcApp app;
  if (!gfc_app_init(&app, args, bundle, &error)) {
    fprintf(stderr, "gui-for-cli-raygui-c: %s\n", error);
    free(error);
    gfc_bundle_free(&bundle);
    gfc_args_free(&args);
    return 1;
  }
  double full_warm_ms = -1.0;
  if (app.args.benchmark_full) {
    struct timespec warm_start;
    struct timespec warm_end;
    clock_gettime(CLOCK_MONOTONIC, &warm_start);
    gfc_app_warm_data_sources(&app);
    clock_gettime(CLOCK_MONOTONIC, &warm_end);
    full_warm_ms = elapsed_ms(warm_start, warm_end);
  }
  SetTraceLogLevel(LOG_WARNING);
  InitWindow(1120, 720, "GUI for CLI Raygui C");
  SetTargetFPS(60);
  SetExitKey(KEY_NULL);

  bool benchmark_printed = false;
  while (!WindowShouldClose()) {
    gfc_app_poll(&app);
    BeginDrawing();
    gfc_ui_draw(&app);
    EndDrawing();
    if (app.args.benchmark && !benchmark_printed) {
      struct timespec frame_ready;
      clock_gettime(CLOCK_MONOTONIC, &frame_ready);
      benchmark_printed = true;
      print_benchmark(&app, elapsed_ms(started, loaded), elapsed_ms(started, frame_ready), full_warm_ms);
      if (app.args.once) {
        break;
      }
    }
  }

  CloseWindow();
  gfc_app_free(&app);
  return 0;
}

int main(int argc, char** argv) {
  return run(argc, argv);
}
