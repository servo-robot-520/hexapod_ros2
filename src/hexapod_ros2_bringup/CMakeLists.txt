cmake_minimum_required(VERSION 3.22)
set(PROJECT_VERSION 0.1.0)
project(hexapod_ros2_bringup VERSION ${PROJECT_VERSION})

if (CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
endif ()

find_package(ament_cmake REQUIRED)

install(DIRECTORY
        launch
        config
        DESTINATION share/${PROJECT_NAME}
)

ament_package()
