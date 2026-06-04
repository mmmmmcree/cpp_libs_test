// Tiny SDL3 + Vulkan demo. Validates that the `features: ["vulkan"]` flag in
// dependencies.json actually reaches the vcpkg manifest — without it,
// SDL3 is built without Vulkan support and SDL_Vulkan_GetInstanceExtensions
// returns nothing. We exit immediately so the demo can be run unattended.

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>

#include <iostream>

int main(int /*argc*/, char* /*argv*/[]) {
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        std::cerr << "SDL_Init failed: " << SDL_GetError() << '\n';
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        "sdl_vulkan_demo", 320, 240, SDL_WINDOW_VULKAN | SDL_WINDOW_HIDDEN);
    if (!window) {
        std::cerr << "SDL_CreateWindow(VULKAN) failed: " << SDL_GetError() << '\n';
        SDL_Quit();
        return 1;
    }

    Uint32 ext_count = 0;
    char const* const* exts = SDL_Vulkan_GetInstanceExtensions(&ext_count);
    if (!exts || ext_count == 0) {
        std::cerr << "SDL_Vulkan_GetInstanceExtensions returned nothing — "
                     "the sdl3[vulkan] feature probably did not land.\n";
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    std::cout << "SDL3 Vulkan instance extensions (" << ext_count << "):\n";
    for (Uint32 i = 0; i < ext_count; ++i) {
        std::cout << "  " << exts[i] << '\n';
    }

    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
