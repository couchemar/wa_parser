cmake_minimum_required(VERSION 3.20)
project(WasmTestData NONE)

# Find all WAT fixture sources
file(GLOB WAT_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/wat/*.wat")

# Custom commands for each WAT file.
# A sibling <name>.wat.flags file supplies extra wat2wasm arguments.
foreach(WAT_FILE ${WAT_SOURCES})
    get_filename_component(BASENAME ${WAT_FILE} NAME_WE)

    set(WAT_DEPS ${WAT_FILE})
    set(WAT_EXTRA_FLAGS "")

    if(EXISTS "${WAT_FILE}.flags")
        file(READ "${WAT_FILE}.flags" FLAG_TEXT)
        string(STRIP "${FLAG_TEXT}" FLAG_TEXT)
        separate_arguments(WAT_EXTRA_FLAGS NATIVE_COMMAND "${FLAG_TEXT}")
        list(APPEND WAT_DEPS "${WAT_FILE}.flags")
    endif()

    # WAT -> WASM
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm
        COMMAND wat2wasm ${WAT_EXTRA_FLAGS} ${WAT_FILE}
                -o ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm
        DEPENDS ${WAT_DEPS}
        COMMENT "Compiling ${BASENAME}.wat"
    )

    list(APPEND WAT_WASM_FILES ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm)
endforeach()

# Main WAT target
add_custom_target(wat_wasm ALL DEPENDS ${WAT_WASM_FILES})
