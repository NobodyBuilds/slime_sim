#include "param.h"
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include "host.h"
#include <algorithm>
#include "cuda.h"

// ── FPS ring buffer ───────────────────────────────────────────────────────────
static float s_fpsHistory[128] = {};
static int   s_fpsOffset = 0;
static float s_fpsAccum = 0.f;
static int   s_fpsSamples = 0;

static void pushFps(float fps) {
    s_fpsAccum += fps;
    s_fpsSamples++;
    if (s_fpsSamples >= 6) {
        s_fpsHistory[s_fpsOffset] = s_fpsAccum / s_fpsSamples;
        s_fpsOffset = (s_fpsOffset + 1) % 128;
        s_fpsAccum = 0.f;
        s_fpsSamples = 0;
    }
}

// ── tooltip helper ────────────────────────────────────────────────────────────
static void tip(const char* desc) {
    ImGui::SetItemTooltip(desc);
}

static bool s_panelOpen = true;

static void debug() {
    bool sync = false;

    // ── collapsed pill ───────────────────────────────────────────────────────
    if (!s_panelOpen) {
        ImGuiWindowFlags pill_flags =
            ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_AlwaysAutoResize;
        ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_Always);
        ImGui::SetNextWindowBgAlpha(0.75f);
        ImGui::Begin("##pill", nullptr, pill_flags);
        ImGui::Text("%.1f fps", settings.avgFps);
        ImGui::SameLine();
        if (ImGui::SmallButton("▼")) s_panelOpen = true;
        ImGui::End();
        return;
    }

    // ── main panel ───────────────────────────────────────────────────────────
    ImGuiWindowFlags panel_flags =
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoScrollbar;
    ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(300, 0), ImGuiCond_Always); // fixed narrow width
    ImGui::SetNextWindowBgAlpha(0.82f);
    ImGui::Begin("Sim Control", nullptr, panel_flags);

    // collapse button
    ImGui::SameLine(ImGui::GetContentRegionAvail().x - 16);
    if (ImGui::SmallButton("▲")) { s_panelOpen = false; ImGui::End(); return; }

    // ── Stats — always visible, never collapsible ─────────────────────────
    float w = ImGui::GetContentRegionAvail().x;
    ImGui::PlotLines("##fps", s_fpsHistory, 128, s_fpsOffset,
        nullptr, 0.f, 165.f, ImVec2(w, 40));

    if (ImGui::BeginTable("fps_table", 3,
        ImGuiTableFlags_BordersInnerV | ImGuiTableFlags_SizingFixedFit)) {
        ImGui::TableSetupColumn("avg", ImGuiTableColumnFlags_WidthFixed, 65);
        ImGui::TableSetupColumn("max", ImGuiTableColumnFlags_WidthFixed, 65);
        ImGui::TableSetupColumn("min", ImGuiTableColumnFlags_WidthFixed, 65);
        ImGui::TableHeadersRow();
        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0); ImGui::Text("%.1f", settings.avgFps);
        ImGui::TableSetColumnIndex(1); ImGui::Text("%.1f", settings.maxFps);
        ImGui::TableSetColumnIndex(2); ImGui::Text("%.1f", settings.minFps);
        ImGui::EndTable();
    }
    ImGui::Text("%dx%d  %d cells", settings.w, settings.h, settings.cells);

    ImGui::Separator();

    // ── Simulation ───────────────────────────────────────────────────────────
    if (ImGui::CollapsingHeader("Simulation")) {
        ImGui::PushItemWidth(-60);
        if (sync |= ImGui::DragFloat("Tile##ts", &settings.tilesize, 0.01f, 0.001f, 900.f, "%.1f"))
            restart();
        
        ImGui::SameLine(); ImGui::TextDisabled("rst");
        tip("World-space size of each grid cell in pixels.\n"
            "Smaller = higher resolution, heavier GPU cost.\n"
            "Changing this restarts the simulation.");
        
        sync |= ImGui::DragFloat("Radius##r", &settings.radius, 0.5f, 1.f, 500.f, "%.1f");
        tip("spawn radius in pixels.\n");
        ImGui::PopItemWidth();
        ImGui::Spacing();
        ImGui::InputInt("agent count", &settings.ncopy);
        if (ImGui::IsItemDeactivatedAfterEdit()) { restart(); }
        
        ImGui::Spacing();
        ImGui::Spacing();
        ImGui::Spacing();
        auto DragFloatRange = [&](const char* label, const char* idMin, float* vMin, const char* idMax, float* vMax, float speed, float minVal, float maxVal) {
            ImGui::TextDisabled("%s", label);

            float shareWidth = ImGui::GetContentRegionAvail().x * 0.5f - ImGui::GetStyle().ItemSpacing.x * 0.5f;

            ImGui::SetNextItemWidth(shareWidth);
            bool changed = ImGui::DragFloat(idMin, vMin, speed, minVal, maxVal, "Min: %.2f");

            ImGui::SameLine();
            ImGui::SetNextItemWidth(-FLT_MIN);
            changed |= ImGui::DragFloat(idMax, vMax, speed, minVal, maxVal, "Max: %.2f");

            return changed;
            };

        
        if (sync |= DragFloatRange("Sensor Angle", "##aMin", &settings.sensorAngle, "##aMax", &settings.sensorAngleMax, 0.01f, 0.f, 50.f)) {
        
			updategenome(1, 3, settings.sensorAngle, settings.sensorAngleMax);
        }
        if (sync |= DragFloatRange("Sensor Distance", "##dMin", &settings.sensorDistance, "##dMax", &settings.sensorDistanceMax, 0.1f, 0.f, 50.f)) {
			updategenome(1, 4, settings.sensorDistance, settings.sensorDistanceMax);

       }
       if( sync |= DragFloatRange("Turn Speed", "##tMin", &settings.turnSpeed, "##tMax", &settings.turnSpeedMax, 0.01f, 0.f, 5.f)){updategenome(2,2, settings.turnSpeed, settings.turnSpeedMax); }
       if( sync |= DragFloatRange("Step Size", "##sMin", &settings.stepSize, "##sMax", &settings.stepSizeMax, 0.01f, 0.f, 50.f)){updategenome(2,3, settings.stepSize, settings.stepSizeMax); }
       if( sync |= DragFloatRange("Deposit Amount", "##depMin", &settings.depositAmount, "##depMax", &settings.depositAmountMax, 0.01f, 0.f, 50.f)){updategenome(2,4, settings.depositAmount, settings.depositAmountMax); }
  
		sync |= ImGui::DragFloat("Decay Factor", &settings.decayFactor, 0.001f, 0.f, 1.f, "%.3f");
		sync |= ImGui::DragFloat("difusion Factor", &settings.diffusionweight, 0.01f, 0.f, 10.f, "%.3f");

    }
    

 

    if (sync) copyparams();

    ImGui::End();
}

extern "C" void ui() {
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    pushFps(settings.avgFps);
    debug();

    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}