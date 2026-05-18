// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ExternApiDemo — showcases ExternEVM's API_CALL precompile (raw URL mode)
/// @notice Milestone 3: precompile decodes ApiRequest and returns mock responses.
///         Milestone 4 will replace mocks with real HTTP calls.
contract ExternApiDemo {
    address constant API_CALL =
        address(0x00000000000000000000000000000000000000AA);

    struct ApiRequest {
        string url;
        string method;
        bytes headers;
        bytes body;
        string responsePath;
        uint8 responseType;
    }

    // -----------------------------------------------------------------------
    // Backward compatibility (Milestone 1/2)
    // -----------------------------------------------------------------------

    /// @notice Calls 0xAA with empty input — returns uint256(1234).
    function getReserveDummy() external view returns (uint256) {
        (bool ok, bytes memory out) = API_CALL.staticcall("");
        require(ok, "API_CALL failed");
        require(out.length == 32, "unexpected output length");
        return abi.decode(out, (uint256));
    }

    // -----------------------------------------------------------------------
    // Weather API demos
    // -----------------------------------------------------------------------

    /// @notice Get temperature as uint256. Mock returns 72.
    function getWeather() external view returns (uint256) {
        ApiRequest memory req = ApiRequest({
            url: "https://api.weather.gov/gridpoints/TOP/31,80/forecast",
            method: "GET",
            headers: bytes(""),
            body: bytes(""),
            responsePath: "properties.periods[0].temperature",
            responseType: 1
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return abi.decode(out, (uint256));
    }

    /// @notice Get weather description as string. Mock returns "Sunny, 72°F".
    function getWeatherDescription() external view returns (string memory) {
        ApiRequest memory req = ApiRequest({
            url: "https://api.weather.gov/gridpoints/TOP/31,80/forecast",
            method: "GET",
            headers: bytes(""),
            body: bytes(""),
            responsePath: "properties.periods[0].shortForecast",
            responseType: 2
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return abi.decode(out, (string));
    }

    // -----------------------------------------------------------------------
    // Price feed demos
    // -----------------------------------------------------------------------

    /// @notice Get gold price as uint256. Mock returns 2340.
    function getGoldPrice() external view returns (uint256) {
        ApiRequest memory req = ApiRequest({
            url: "https://api.metals.live/v1/spot/gold",
            method: "GET",
            headers: bytes(""),
            body: bytes(""),
            responsePath: "price",
            responseType: 1
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return abi.decode(out, (uint256));
    }

    /// @notice Get bitcoin price as uint256. Mock returns 104000.
    function getBitcoinPrice() external view returns (uint256) {
        ApiRequest memory req = ApiRequest({
            url: "https://api.coindesk.com/v1/bpi/currentprice.json",
            method: "GET",
            headers: bytes(""),
            body: bytes(""),
            responsePath: "bpi.USD.rate_float",
            responseType: 1
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return abi.decode(out, (uint256));
    }

    // -----------------------------------------------------------------------
    // Fun / misc demos
    // -----------------------------------------------------------------------

    /// @notice Get a random joke as string.
    ///         Mock returns: "Why did the smart contract go to therapy? Too many trust issues."
    function getRandomJoke() external view returns (string memory) {
        ApiRequest memory req = ApiRequest({
            url: "https://official-joke-api.appspot.com/random_joke",
            method: "GET",
            headers: bytes(""),
            body: bytes(""),
            responsePath: "setup",
            responseType: 2
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return abi.decode(out, (string));
    }

    // -----------------------------------------------------------------------
    // Power functions — fully customizable
    // -----------------------------------------------------------------------

    /// @notice Call any API with custom URL, method, responsePath, and responseType.
    ///         Returns raw bytes — caller decodes based on their responseType.
    function callCustomApi(
        string calldata url,
        string calldata method,
        string calldata responsePath,
        uint8 responseType
    ) external view returns (bytes memory) {
        ApiRequest memory req = ApiRequest({
            url: url,
            method: method,
            headers: bytes(""),
            body: bytes(""),
            responsePath: responsePath,
            responseType: responseType
        });

        (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
        require(ok, "API_CALL failed");
        return out;
    }

    /// @notice Raw bytes in, raw bytes out — for debugging the precompile directly.
    function rawApiCall(bytes calldata data) external view returns (bytes memory) {
        (bool ok, bytes memory out) = API_CALL.staticcall(data);
        require(ok, "API_CALL failed");
        return out;
    }
}