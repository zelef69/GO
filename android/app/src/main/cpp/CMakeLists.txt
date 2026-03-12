cmake_minimum_required(VERSION 3.22.1)

project(go_play_security)

add_library(
    go_play_security
    SHARED
    security_native.cpp
)

find_library(
    log-lib
    log
)

target_compile_features(go_play_security PRIVATE cxx_std_17)
target_compile_options(
    go_play_security
    PRIVATE
    -fvisibility=hidden
    -fstack-protector-strong
    -D_FORTIFY_SOURCE=2
)

target_link_libraries(
    go_play_security
    ${log-lib}
)
