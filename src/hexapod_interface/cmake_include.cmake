if (NOT ROS2_WS_SOURCE_BUILD OR NOT TARGET hexapod_interface)
    find_package(hexapod_interface REQUIRED)
endif ()

if (ROS2_WS_SOURCE_BUILD AND TARGET hexapod_interface)
    rosidl_get_typesupport_target(hexapod_interface_CPP_TYPESUPPORT_TARGET
            hexapod_interface
            "rosidl_typesupport_cpp"
    )
    rosidl_get_typesupport_target(hexapod_interface_FASTRTPS_CPP_TYPESUPPORT_TARGET
            hexapod_interface
            "rosidl_typesupport_fastrtps_cpp"
    )
    rosidl_get_typesupport_target(hexapod_interface_INTROSPECTION_CPP_TYPESUPPORT_TARGET
            hexapod_interface
            "rosidl_typesupport_introspection_cpp"
    )
    if (hexapod_interface_CPP_TYPESUPPORT_TARGET MATCHES "-NOTFOUND$"
            OR hexapod_interface_FASTRTPS_CPP_TYPESUPPORT_TARGET MATCHES "-NOTFOUND$"
            OR hexapod_interface_INTROSPECTION_CPP_TYPESUPPORT_TARGET MATCHES "-NOTFOUND$")
        message(FATAL_ERROR "The in-tree hexapod_interface target does not provide rosidl_typesupport_cpp.")
    endif ()
    if (NOT DEFINED hexapod_interface_SOURCE_DIR
            OR NOT IS_DIRECTORY "${hexapod_interface_SOURCE_DIR}/include")
        message(FATAL_ERROR "The in-tree hexapod_interface source include directory is unavailable.")
    endif ()
    target_link_libraries(${PROJECT_NAME}
            ${hexapod_interface_CPP_TYPESUPPORT_TARGET}
    )
    target_include_directories(${PROJECT_NAME} PUBLIC
            "$<BUILD_INTERFACE:${hexapod_interface_SOURCE_DIR}/include>")
else ()
    ament_target_dependencies(${PROJECT_NAME} hexapod_interface)
endif ()

if (ROS2_WS_SOURCE_BUILD)
    target_link_libraries(${PROJECT_NAME}
            "-Wl,--no-as-needed"
            ${hexapod_interface_FASTRTPS_CPP_TYPESUPPORT_TARGET}
            ${hexapod_interface_INTROSPECTION_CPP_TYPESUPPORT_TARGET}
            "-Wl,--as-needed"
    )
endif ()