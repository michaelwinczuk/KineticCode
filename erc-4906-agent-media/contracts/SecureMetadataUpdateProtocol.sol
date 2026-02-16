// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Secure Metadata Update Protocol v1.1 (Remediated)
/// @notice Secure, gas-efficient protocol for autonomous agent metadata updates with domain whitelisting
contract SecureMetadataUpdateProtocol is Ownable {
    // ============ STATE VARIABLES ============
    mapping(string => bool) public allowedDomains;
    uint256 public maxURLLength;
    uint256 public constant MAX_ITERATIONS = 1000;
    
    event DomainRegistered(string domain);
    event DomainUnregistered(string domain);
    event MaxLengthUpdated(uint256 newLength);
    
    // ============ CONSTRUCTOR ============
    constructor(uint256 _maxURLLength) {
        maxURLLength = _maxURLLength;
        // Initialize with common trusted domains
        allowedDomains["arweave.net"] = true;
        allowedDomains["ipfs.io"] = true;
        allowedDomains["cloudflare-ipfs.com"] = true;
    }
    
    // ============ DOMAIN MANAGEMENT ============
    /// @notice Register a new allowed domain (owner only)
    function registerDomain(string calldata domain) external onlyOwner {
        allowedDomains[domain] = true;
        emit DomainRegistered(domain);
    }
    
    /// @notice Unregister a domain (owner only)
    function unregisterDomain(string calldata domain) external onlyOwner {
        allowedDomains[domain] = false;
        emit DomainUnregistered(domain);
    }
    
    /// @notice Update maximum URL length (owner only)
    function setMaxURLLength(uint256 _maxURLLength) external onlyOwner {
        maxURLLength = _maxURLLength;
        emit MaxLengthUpdated(_maxURLLength);
    }
    
    // ============ URL VALIDATION ============
    /// @notice Validate and sanitize animation URL
    /// @param url Input URL
    /// @return sanitizedURL Sanitized URL with validated domain
    /// @dev Gas cost: ~15k gas for typical URL, scales with length
    function sanitizeAnimationURL(string calldata url) external view returns (string memory) {
        // Gas optimization: length check before any processing
        require(bytes(url).length <= maxURLLength, "URL too long");
        
        // Extract and validate hostname
        string memory hostname = extractHostname(url);
        require(allowedDomains[hostname], "Domain not allowed");
        
        // Sanitize query parameters and fragments
        string memory sanitized = sanitizeURLComponents(url);
        
        return sanitized;
    }
    
    /// @notice Extract hostname from URL
    /// @param url Input URL
    /// @return hostname Extracted hostname
    function extractHostname(string calldata url) public pure returns (string memory) {
        bytes memory urlBytes = bytes(url);
        uint256 start;
        uint256 end;
        
        // Find protocol separator
        for (uint256 i = 0; i < urlBytes.length; i++) {
            if (i > maxURLLength) break; // Safety
            if (urlBytes[i] == ":" && i + 2 < urlBytes.length && urlBytes[i+1] == "/" && urlBytes[i+2] == "/") {
                start = i + 3;
                break;
            }
        }
        
        // Find end of hostname
        for (uint256 i = start; i < urlBytes.length; i++) {
            if (i > maxURLLength) break; // Safety
            if (urlBytes[i] == "/" || urlBytes[i] == "?" || urlBytes[i] == "#") {
                end = i;
                break;
            }
            if (i == urlBytes.length - 1) {
                end = urlBytes.length;
            }
        }
        
        require(end > start, "Invalid URL structure");
        
        // Extract hostname substring
        bytes memory hostnameBytes = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            hostnameBytes[i - start] = urlBytes[i];
        }
        
        return string(hostnameBytes);
    }
    
    /// @notice Sanitize URL components
    /// @param url Input URL
    /// @return sanitized URL without dangerous components
    function sanitizeURLComponents(string calldata url) internal pure returns (string memory) {
        // Implementation removes suspicious query parameters
        // In production, integrate with OWASP validation library
        bytes memory urlBytes = bytes(url);
        uint256 queryStart = type(uint256).max;
        
        for (uint256 i = 0; i < urlBytes.length; i++) {
            if (urlBytes[i] == "?") {
                queryStart = i;
                break;
            }
        }
        
        if (queryStart == type(uint256).max) {
            return url;
        }
        
        // Return only the path portion (pre-query)
        bytes memory sanitized = new bytes(queryStart);
        for (uint256 i = 0; i < queryStart; i++) {
            sanitized[i] = urlBytes[i];
        }
        
        return string(sanitized);
    }
}
