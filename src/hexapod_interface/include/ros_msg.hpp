#pragma once

#include <algorithm>
#include <stdexcept>
#include <string>
#include <string_view>


namespace hexapod_interface {

    namespace detail {

        [[nodiscard]] constexpr bool
        is_ascii_whitespace(const char character) noexcept {
            return character == ' ' || (character >= '\t' && character <= '\r');
        }

        [[nodiscard]] inline bool
        is_empty_or_ascii_whitespace(const std::string_view value) noexcept {
            if (value.empty()) {
                return true;
            }
            return std::ranges::all_of(value.begin(), value.end(), is_ascii_whitespace);
        }

        /// Only do the minimum verification required for endpoint splicing
        /// the caller should provide the ROS normalized FQN
        inline void require_prefix(const std::string_view prefix) {
            if (is_empty_or_ascii_whitespace(prefix) || prefix == "~/" ||
                prefix.find_first_of(" \t\n\r\v\f") != std::string_view::npos) {
                throw std::invalid_argument(
                    R"(prefix must be without ASCII whitespace and '\t\n\r\v\f')");
            }
        }

        [[nodiscard]] inline std::string
        normalized_prefix(const std::string_view prefix) {
            require_prefix(prefix);
            auto normalized = prefix;
            while (normalized.size() > 1 && normalized.back() == '/') {
                normalized.remove_suffix(1);
            }
            return std::string{normalized};
        }


        /// @param prefix Can be a node name or a node's fully qualified name
        /// @param endpoint_suffix Path behind node
        /// @return
        [[nodiscard]] inline std::string
        endpoint_name(const std::string_view prefix,
                      const std::string_view endpoint_suffix) {
            return normalized_prefix(prefix) + "~/" + std::string{endpoint_suffix};
        }

        inline constexpr std::string_view nodeName = "xxx";
    } // namespace detail

    /// Verify the stable device identity used as a ROS path segment
    inline void require_device_id(const std::string_view device_id) {
        if (detail::is_empty_or_ascii_whitespace(device_id) ||
            device_id.find_first_of("~/ \t\n\r\v\f") != std::string_view::npos) {
            throw std::invalid_argument(
                R"(device_id must not be empty and not contain '/', ASCII whitespace and \t\n\r\v\f)");
        }
    }

    // kPrivateTopic names


    // kPrivateSrv names


    // Topic functions


} // namespace hexapod_interface
