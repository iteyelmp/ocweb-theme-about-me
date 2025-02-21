// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./library/LibStrings.sol";

struct KeyValue {
    string key;
    string value;
}

// EIP-5219 interface
interface IDecentralizedApp {
    /// @notice                     Send an HTTP GET-like request to this contract
    /// @param  resource            The resource to request (e.g. "/asdf/1234" turns in to `["asdf", "1234"]`)
    /// @param  params              The query parameters. (e.g. "?asdf=1234&foo=bar" turns in to `[{ key: "asdf", value: "1234" }, { key: "foo", value: "bar" }]`)
    /// @return statusCode          The HTTP status code (e.g. 200)
    /// @return body                The body of the response
    /// @return headers             A list of header names (e.g. [{ key: "Content-Type", value: "application/json" }])
    function request(string[] memory resource, KeyValue[] memory params) external view returns (uint statusCode, string memory body, KeyValue[] memory headers);
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IVersionableWebsite is IDecentralizedApp, IOwnable {
    struct LinkedListNodePlugin {
        IVersionableWebsitePlugin plugin;
        uint96 next;
    }
    struct WebsiteVersion {
        string description;

        // The list of enabled plugins for this version
        // Linked list for the execution order
        LinkedListNodePlugin[] pluginNodes;
        uint96 headPluginLinkedList;

        // When not the live version, a frontend version can be viewed by this address,
        // which is a clone of a cheap proxy contract
        IVersionableWebsiteViewer viewer;
        bool isViewable;

        // A lock at the version level: Plugins cannot be added, edited, or removed
        // Only the isViewable toggle can be changed
        bool locked;
    }

    function liveWebsiteVersionIndex() external view returns (uint256);
    function setLiveWebsiteVersionIndex(uint256 index) external;
    // Shortcut for frontends
    function getLiveWebsiteVersion() external view returns (WebsiteVersion memory websiteVersion, uint256 websiteVersionIndex);

    function addWebsiteVersion(string memory description, uint copyPluginsFromWebsiteVersionIndex) external;
    function getWebsiteVersionCount() external view returns (uint);
    function getWebsiteVersions(uint startIndex, uint count) external view returns (WebsiteVersion[] memory, uint totalCount);
    function getWebsiteVersion(uint256 websiteVersionIndex) external view returns (WebsiteVersion memory);
    function renameWebsiteVersion(uint256 websiteVersionIndex, string memory newDescription) external;

    // Lock a website version: It won't be editable anymore
    function lockWebsiteVersion(uint256 websiteVersionIndex) external;
    // Lock the whole website
    function lock() external;
    function isLocked() external view returns (bool);


    // Enable/disable the viewer, for a frontend version which is not the live one
    function enableViewerForWebsiteVersion(uint256 websiteVersionIndex, bool enable) external;

    function addPlugin(uint websiteVersionIndex, IVersionableWebsitePlugin plugin, uint position) external;
    struct IVersionableWebsitePluginWithInfos {
        IVersionableWebsitePlugin plugin;
        IVersionableWebsitePlugin.Infos infos;
    }
    function getPlugins(uint websiteVersionIndex) external view returns (IVersionableWebsitePluginWithInfos[] memory pluginWithInfos);
    function reorderPlugin(uint websiteVersionIndex, IVersionableWebsitePlugin plugin, uint newPosition) external;
    function removePlugin(uint websiteVersionIndex, address plugin) external;

    function requestWebsiteVersion(uint256 websiteVersionIndex, string[] memory resource, KeyValue[] memory params) external view returns (uint statusCode, string memory body, KeyValue[] memory headers);
    function clearPathCache(uint256 websiteVersionIndex, string[] memory paths) external;
}

interface IVersionableWebsitePlugin is IERC165 {
    enum AdminPanelType {
        Primary,
        Secondary
    }
    // Represent an admin panel for this plugin
    // 2 types :
    // - An autonomous webpage (which can be iframed by global admin panels)
    // - A UMD module which is loaded by a global admin panel
    //   In this case, the moduleForGlobalAdminPanel is the address of the
    //   admin panel plugin for which this plugin is a module
    struct AdminPanel {
        // Title of the panel, can be empty
        string title;
        // The web3:// URL of the panel (either a HTML webpage, or a JS module)
        string url;

        // If the panel is a module, this is the address of the admin panel plugin
        // for which this plugin is a module
        IVersionableWebsitePlugin moduleForGlobalAdminPanel;

        // The type of the panel
        // This is mostly an hint on how to embed the panel
        // Primary will be for a full page, Secondary will be for being inserted inside
        // a common Settings page
        AdminPanelType panelType;
    }

    struct Infos {
        // Technical name
        string name;
        // Version of the plugin
        string version;
        // Display name
        string title;
        string subTitle;
        // Author
        string author;
        // Point to a web3:// address of the homepage
        string homepage;

        // Dependencies of this plugin
        IVersionableWebsitePlugin[] dependencies;

        // Admin panels
        AdminPanel[] adminPanels;
    }
    function infos() external view returns (Infos memory);

    function rewriteWeb3Request(IVersionableWebsite website, uint websiteVersionIndex, string[] memory resource, KeyValue[] memory params) external view returns (bool rewritten, string[] memory newResource, KeyValue[] memory newParams);

    function processWeb3Request(IVersionableWebsite website, uint websiteVersionIndex, string[] memory resource, KeyValue[] memory params) external view returns (uint statusCode, string memory body, KeyValue[] memory headers);

    function copyFrontendSettings(IVersionableWebsite website, uint fromWebsiteVersionIndex, uint toWebsiteVersionIndex) external;
}

interface IVersionableWebsiteViewer is IDecentralizedApp {

    function clearPathCache(string[] memory paths) external;
}

contract ThemeAboutMePlugin is ERC165, IVersionableWebsitePlugin {
    IDecentralizedApp public frontend;
    IVersionableWebsitePlugin public staticFrontendPlugin;
    IVersionableWebsitePlugin public ocWebAdminPlugin;

    struct Config {
        string[] rootPath;
    }
    mapping(IVersionableWebsite => mapping(uint => Config)) private configs;

    constructor(IDecentralizedApp _frontend, IVersionableWebsitePlugin _staticFrontendPlugin, IVersionableWebsitePlugin _ocWebAdminPlugin) {
        frontend = _frontend;
        staticFrontendPlugin = _staticFrontendPlugin;
        ocWebAdminPlugin = _ocWebAdminPlugin;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IVersionableWebsitePlugin).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function infos() external view returns (Infos memory) {
        IVersionableWebsitePlugin[] memory dependencies = new IVersionableWebsitePlugin[](2);
        dependencies[0] = staticFrontendPlugin;
        dependencies[1] = ocWebAdminPlugin;

        AdminPanel[] memory adminPanels = new AdminPanel[](1);
        adminPanels[0] = AdminPanel({
            title: "Theme About Me",
            url: "/themes/about-me/admin.umd.js",
            moduleForGlobalAdminPanel: ocWebAdminPlugin,
            panelType: AdminPanelType.Secondary
        });
        // adminPanels[1] = AdminPanel({
        //     title: "Theme About Me",
        //     url: "/themes/about-me/admin.umd.js",
        //     moduleForGlobalAdminPanel: ocWebAdminPlugin,
        //     panelType: AdminPanelType.Secondary
        // });

        return
            Infos({
                name: "themeAboutMe",
                version: "0.1.1",
                title: "Theme About Me",
                subTitle: "A theme for presenting oneself",
                author: "nand",
                homepage: "web3://ocweb.eth/",
                dependencies: dependencies,
                adminPanels: adminPanels
            });
    }

    function rewriteWeb3Request(IVersionableWebsite website, uint websiteVersionIndex, string[] memory resource, KeyValue[] memory params) external view returns (bool rewritten, string[] memory newResource, KeyValue[] memory newParams) {
        return (false, new string[](0), new KeyValue[](0));
    }

    function processWeb3Request(
        IVersionableWebsite website,
        uint websiteVersionIndex,
        string[] memory resource,
        KeyValue[] memory params
    )
        external view override returns (uint statusCode, string memory body, KeyValue[] memory headers)
    {
        // Serve the admin parts : /themes/about-me/* -> /themes/about-me/*
        if(resource.length >= 2 && Strings.equal(resource[0], "themes") && Strings.equal(resource[1], "about-me")) {
            (statusCode, body, headers) = frontend.request(resource, params);

            // If there is a "Cache-control: evm-events" header, we will replace it with 
            // "Cache-control: evm-events=<addressOfFrontend>"
            // That way, we indicate that the contract emitting the cache clearing events is 
            // the frontend website
            for(uint i = 0; i < headers.length; i++) {
                if(LibStrings.compare(headers[i].key, "Cache-control") && LibStrings.compare(headers[i].value, "evm-events")) {
                    headers[i].value = string.concat("evm-events=", LibStrings.toHexString(address(frontend)));
                }
            }

            return (statusCode, body, headers);
        }

        // Serve the frontend : Proxy /[config.rootPath]/* -> /*
        Config memory config = configs[website][websiteVersionIndex];
        if(resource.length >= config.rootPath.length) {
            bool prefixMatch = true;
            for(uint i = 0; i < config.rootPath.length; i++) {
                if(Strings.equal(resource[i], config.rootPath[i]) == false) {
                    prefixMatch = false;
                    break;
                }
            }

            if(prefixMatch) {
                string[] memory newResource = new string[](resource.length - config.rootPath.length);
                for(uint i = 0; i < resource.length - config.rootPath.length; i++) {
                    newResource[i] = resource[i + config.rootPath.length];
                }

                (statusCode, body, headers) = frontend.request(newResource, params);

                // If there is a "Cache-control: evm-events" header, we will replace it with 
                // "Cache-control: evm-events=<addressOfFrontend><newResourcePath>"
                // We only include <newResourcePath> if config.rootPath is not empty, otherwise the
                // path of the cache clearing event will be the same than the path of the URL
                // That way, we indicate that the contract emitting the cache clearing events is 
                // the frontend website
                for(uint i = 0; i < headers.length; i++) {
                    if(LibStrings.compare(headers[i].key, "Cache-control") && LibStrings.compare(headers[i].value, "evm-events")) {
                        string memory path = "";
                        string memory cacheDirectiveValueQuote = "";
                        if(config.rootPath.length > 0) {
                            cacheDirectiveValueQuote = "\"";
                            path = "/";
                            for(uint j = 0; j < newResource.length; j++) {
                                path = string.concat(path, newResource[j]);
                                if(j < newResource.length - 1) {
                                    path = string.concat(path, "/");
                                }
                            }
                        }

                        headers[i].value = string.concat("evm-events=", cacheDirectiveValueQuote, LibStrings.toHexString(address(frontend)), path, cacheDirectiveValueQuote);
                    }
                }

                return (statusCode, body, headers);
            }
        }
    }

    function copyFrontendSettings(IVersionableWebsite website, uint fromFrontendIndex, uint toFrontendIndex) public {
        require(address(website) == msg.sender);

        Config storage config = configs[website][toFrontendIndex];
        Config storage fromConfig = configs[website][fromFrontendIndex];

        config.rootPath = fromConfig.rootPath;
    }

    function getConfig(IVersionableWebsite website, uint websiteVersionIndex) external view returns (Config memory) {
        return configs[website][websiteVersionIndex];
    }

    function setConfig(IVersionableWebsite website, uint websiteVersionIndex, Config memory _config) external {
        require(address(website) == msg.sender || website.owner() == msg.sender, "Not the owner");

        require(website.isLocked() == false, "Website is locked");

        require(websiteVersionIndex < website.getWebsiteVersionCount(), "Website version out of bounds");
        IVersionableWebsite.WebsiteVersion memory websiteVersion = website.getWebsiteVersion(websiteVersionIndex);
        require(websiteVersion.locked == false, "Website version is locked");

        Config storage config = configs[website][websiteVersionIndex];

        config.rootPath = _config.rootPath;
    }
}
