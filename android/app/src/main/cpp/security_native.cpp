#include <jni.h>
#include <string>
#include <vector>
#include <fstream>
#include <algorithm>
#include <cstring>
#include <cerrno>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/time.h>

namespace {

std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

bool containsAnyToken(const std::string& haystackLower, const std::vector<std::string>& tokens) {
    for (const auto& token : tokens) {
        if (haystackLower.find(token) != std::string::npos) {
            return true;
        }
    }
    return false;
}

bool scanMapsForSuspiciousTokens() {
    std::ifstream maps("/proc/self/maps");
    if (!maps.is_open()) {
        return false;
    }

    static const std::vector<std::string> kTokens = {
        "frida",
        "gum-js-loop",
        "gadget",
        "xposed",
        "lsposed",
        "edxp",
        "substrate",
        "riru",
    };

    std::string line;
    while (std::getline(maps, line)) {
        const auto lower = toLower(line);
        if (containsAnyToken(lower, kTokens)) {
            return true;
        }
    }
    return false;
}

bool hasTracerPid() {
    std::ifstream status("/proc/self/status");
    if (!status.is_open()) {
        return false;
    }
    std::string line;
    while (std::getline(status, line)) {
        if (line.rfind("TracerPid:", 0) == 0) {
            auto value = line.substr(std::strlen("TracerPid:"));
            value.erase(std::remove_if(value.begin(), value.end(), ::isspace), value.end());
            return value != "0" && !value.empty();
        }
    }
    return false;
}

bool connectToLocalPort(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return false;
    }

    timeval timeout{};
    timeout.tv_sec = 0;
    timeout.tv_usec = 120000;  // 120ms
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(static_cast<uint16_t>(port));
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    bool connected = connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0;
    close(fd);
    return connected;
}

bool scanKnownFridaPorts() {
    static const std::vector<int> kPorts = {
        27042, 27043, 23946, 27049,
    };
    for (int port : kPorts) {
        if (connectToLocalPort(port)) {
            return true;
        }
    }
    return false;
}

bool constantTimeEquals(const std::string& left, const std::string& right) {
    if (left.size() != right.size()) {
        return false;
    }
    unsigned char diff = 0;
    for (size_t i = 0; i < left.size(); ++i) {
        diff |= static_cast<unsigned char>(left[i] ^ right[i]);
    }
    return diff == 0;
}

std::string jstringToUtf8(JNIEnv* env, jstring value) {
    if (value == nullptr) {
        return "";
    }
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) {
        return "";
    }
    std::string out(chars);
    env->ReleaseStringUTFChars(value, chars);
    return out;
}

}  // namespace

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_go_1play_security_SecurityNativeBridge_nativeIsTracerAttached(
    JNIEnv* /*env*/,
    jclass /*clazz*/
) {
    return hasTracerPid() ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_go_1play_security_SecurityNativeBridge_nativeHasSuspiciousMaps(
    JNIEnv* /*env*/,
    jclass /*clazz*/
) {
    return scanMapsForSuspiciousTokens() ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_go_1play_security_SecurityNativeBridge_nativeScanFridaPorts(
    JNIEnv* /*env*/,
    jclass /*clazz*/
) {
    return scanKnownFridaPorts() ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_go_1play_security_SecurityNativeBridge_nativeConstantTimeEquals(
    JNIEnv* env,
    jclass /*clazz*/,
    jstring left,
    jstring right
) {
    const auto leftValue = jstringToUtf8(env, left);
    const auto rightValue = jstringToUtf8(env, right);
    return constantTimeEquals(leftValue, rightValue) ? JNI_TRUE : JNI_FALSE;
}
