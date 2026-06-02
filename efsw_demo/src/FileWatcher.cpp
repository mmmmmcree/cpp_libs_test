#include "FileWatcher.hpp"

#include <efsw/efsw.hpp>

#include <iostream>

namespace demo {

namespace {
const char* actionName(efsw::Action action) {
    switch (action) {
        case efsw::Actions::Add:      return "Add";
        case efsw::Actions::Delete:   return "Delete";
        case efsw::Actions::Modified: return "Modified";
        case efsw::Actions::Moved:    return "Moved";
    }
    return "Unknown";
}
} // namespace

class FileWatcher::Listener final : public efsw::FileWatchListener {
public:
    // Matches efsw 1.5.1 release API: oldFilename is `std::string` by value.
    void handleFileAction(efsw::WatchID         watchid,
                          const std::string&    dir,
                          const std::string&    filename,
                          efsw::Action          action,
                          std::string           oldFilename) override {
        std::cout << "[watch " << watchid << "] "
                  << actionName(action) << ": "
                  << dir << filename;
        if (action == efsw::Actions::Moved && !oldFilename.empty()) {
            std::cout << " (from " << oldFilename << ")";
        }
        std::cout << std::endl;
    }
};

FileWatcher::FileWatcher()
    : listener_(std::make_unique<Listener>()),
      watcher_(std::make_unique<efsw::FileWatcher>()) {}

FileWatcher::~FileWatcher() = default;

bool FileWatcher::addWatch(const std::string& path, bool recursive) {
    const efsw::WatchID id =
        watcher_->addWatch(path, listener_.get(), recursive);
    if (id < 0) {
        std::cerr << "addWatch failed for \"" << path
                  << "\" (efsw error " << id << ")" << std::endl;
        return false;
    }
    std::cout << "Watching \"" << path << "\""
              << " (recursive=" << std::boolalpha << recursive
              << ", id=" << id << ")" << std::endl;
    return true;
}

void FileWatcher::start() {
    watcher_->watch();
}

} // namespace demo
