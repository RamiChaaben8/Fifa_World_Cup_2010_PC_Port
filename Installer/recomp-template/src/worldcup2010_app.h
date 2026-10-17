// worldcup2010 - ReXGlue Recompiled Project
//
// Customize your app by overriding virtual hooks from rex::ReXApp.

#pragma once

#include <rex/rex_app.h>
#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/ui/window.h>

class WorldCup2010App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<WorldCup2010App>(new WorldCup2010App(ctx, "worldcup2010",
        PPCImageConfig));
  }

  void OnPreSetup(rex::RuntimeConfig& config) override {
    if (config.gpu_plugin.empty()) {
      config.gpu_plugin = "xenos";
    }
  }

  void OnConfigurePaths(rex::PathConfig& paths) override {
    if (paths.game_data_root.empty()) {
      const auto executable_folder = rex::filesystem::GetExecutableFolder();
      for (const auto& candidate : {executable_folder, executable_folder / "GameData",
                                   executable_folder.parent_path() / "GameData",
                                   executable_folder.parent_path()}) {
        std::error_code error;
        if (std::filesystem::is_regular_file(candidate / "default.xex", error)) {
          paths.game_data_root = candidate;
          break;
        }
      }
    }
  }

  void OnCreateDialogs(rex::ui::ImGuiDrawer*) override {
    window()->SetTitle("2010 FIFA World Cup South Africa PC");
  }

  void OnPostSetup() override {
    rex::cvar::SetFlagByName("gpu_allow_invalid_fetch_constants", "true");
  }
};
