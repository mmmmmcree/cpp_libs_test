#pragma once

#include <memory>
#include <string>

// Forward-declare efsw types so this header doesn't pull in the library
// for downstream consumers.
namespace efsw {
class FileWatcher;
}

namespace demo {

// Composition-based wrapper around efsw::FileWatcher.
// The internal listener is owned by this class and forwards events to stdout.
class FileWatcher {
public:
    FileWatcher();
    ~FileWatcher();

    FileWatcher(const FileWatcher&)            = delete;
    FileWatcher& operator=(const FileWatcher&) = delete;
    FileWatcher(FileWatcher&&)                 = delete;
    FileWatcher& operator=(FileWatcher&&)      = delete;

    // Adds a directory watch. Returns true on success.
    bool addWatch(const std::string& path, bool recursive = true);

    // Begin asynchronous watching. Non-blocking; events are delivered on
    // an internal efsw thread.
    void start();

private:
    class Listener; // pImpl-style listener defined in the .cpp

    // Order matters for destruction: the watcher must be destroyed BEFORE
    // the listener, otherwise an in-flight callback could touch a freed
    // listener. unique_ptr members are destroyed in reverse declaration
    // order, so declare listener_ first and watcher_ last.
    std::unique_ptr<Listener>          listener_;
    std::unique_ptr<efsw::FileWatcher> watcher_;
};

} // namespace demo
