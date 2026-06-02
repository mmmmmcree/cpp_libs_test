#include "FileWatcher.hpp"

#include <filesystem>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    const std::string path =
        (argc >= 2) ? std::string(argv[1])
                    : std::filesystem::current_path().string();

    demo::FileWatcher fw;
    if (!fw.addWatch(path, /*recursive=*/true)) {
        return 1;
    }
    fw.start();

    std::cout << "[efsw_cmake_demo] Watching... press Enter to exit."
              << std::endl;

    // Block until the user hits Enter.
    std::string line;
    std::getline(std::cin, line);

    std::cout << "Bye." << std::endl;
    return 0;
}
