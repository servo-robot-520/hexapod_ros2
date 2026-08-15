import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    hexapod_controller_pkg = get_package_share_directory("hexapod_controller")

    use_sim_time = LaunchConfiguration("use_sim_time", default="false")

    controller_config = os.path.join(
        hexapod_controller_pkg, "config", "hexapod_controller.yaml"
    )

    hexapod_controller_node = Node(
        package="hexapod_controller",
        executable="hexapod_controller_node",
        name="hexapod_controller",
        parameters=[
            controller_config,
            {"use_sim_time": use_sim_time},
        ],
        output="screen",
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            "use_sim_time",
            default_value="false",
            description="Use simulation (Gazebo) clock if true",
        ),
        hexapod_controller_node,
    ])