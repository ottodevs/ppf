pragma solidity 0.4.24;

import "./Feed.sol";
import "./zep/ECRecovery.sol";


contract PPF is Feed {
    using ECRecovery for bytes32;
    
    struct Price {
        uint128 xrt;
        uint64 when;
    }
    
    mapping (bytes32 => Price) private feed;
    address public operator;
    address public operatorOwner;

    uint256 constant public ONE = 10 ** 18; // 10^18 is considered 1 in the price feed to allow for decimal calculations
    bytes32 constant private PPF_v1_ID = 0x33a8ba7202230fa1cee2aac7bac322939edc7ba0a48b0989335a5f87a5770369; // keccak256("PPF-v1"); 
    
    event SetRate(address indexed base, address indexed quote, uint256 xrt, uint64 when);
    event SetOperator(address indexed operator);
    event SetOperatorOwner(address indexed operatorOwner);
    
    /**
    * @param _operator Public key allowed to sign messages to update the pricefeed
    * @param _operatorOwner Address of an account that can change the operator
    */
    constructor (address _operator, address _operatorOwner) public {
        _setOperator(_operator);
        _setOperatorOwner(_operatorOwner);
    }
    
    /**
    * @notice Update the price for the `base + ':' + quote` feed with an exchange rate of `xrt / ONE` for time `when`
    * @dev If the number representation of base is lower than the one for quote, and update is cheaper, as less manipulation is required.
    * @param base Address for the base token in the feed
    * @param quote Address for the quote token the base is denominated in
    * @param xrt Exchange rate for base denominated in quote. 10^18 is considered 1 to allow for decimal calculations
    * @param when Timestamp for the exchange rate value
    * @param sig Signature payload (EIP191) from operator, concatenated [  r  ][  s  ][v]. See setHash function for the hash calculation. 
    */
    function update(address base, address quote, uint128 xrt, uint64 when, bytes sig) external {
        bytes32 pair = pairId(base, quote);

        // Ensure it is more recent than the current value (implicit check for > 0) and not a future date
        require(when > feed[pair].when && when <= block.timestamp);
        require(xrt > 0); // Make sure xrt is not 0, as the math would break (Dividing by 0 sucks big time)
        require(base != quote); // Assumption that currency units are fungible and xrt should always be 1
        
        bytes32 h = setHash(base, quote, xrt, when);
        require(h.personalRecover(sig) == operator); // Make sure the update was signed by the operator

        feed[pair] = Price(pairXRT(base, quote, xrt), when);
        
        emit SetRate(base, quote, xrt, when);
    }
    
    /**
    * @param base Address for the base token in the feed
    * @param quote Address for the quote token the base is denominated in
    * @return XRT for base:quote and the timestamp when it was updated  
    */
    function get(address base, address quote) public view returns (uint128, uint64) {
        Price storage price = feed[pairId(base, quote)];
        
        // if never set, return 0.
        if (price.when == 0) {
            return (0, 0);
        }
        
        return (pairXRT(base, quote, price.xrt), price.when);
    }
    
    /**
    * @notice Set operator public key to `_operator`
    * @param _operator Public key allowed to sign messages to update the pricefeed
    */
    function setOperator(address _operator) external {
        require(msg.sender == operator || msg.sender == operatorOwner);
        _setOperator(_operator);
    }

    /**
    * @notice Set operator owner to `_operatorOwner` 
    * @param _operatorOwner Address of an account that can change the operator
    */
    function setOperatorOwner(address _operatorOwner) external {
        require(msg.sender == operatorOwner);
        _setOperatorOwner(_operatorOwner);
    }
    
    function _setOperator(address _operator) internal {
        require(_operator != address(0));
        operator = _operator;
        emit SetOperator(_operator);
    }

    function _setOperatorOwner(address _operatorOwner) internal {
        require(_operatorOwner != address(0));
        operatorOwner = _operatorOwner;
        emit SetOperatorOwner(_operatorOwner);
    }
    
    /**
    * @dev pairId returns a unique id for each pair, regardless of the order of base and quote
    */
    function pairId(address base, address quote) private pure returns (bytes32) {
        bool pairOrdered = isPairOrdered(base, quote);
        address orderedBase = pairOrdered ? base : quote;
        address orderedQuote = pairOrdered ? quote : base;
        
        return keccak256(abi.encodePacked(orderedBase, orderedQuote));
    }

    /**
    * @dev Compute xrt depending on base and quote order.
    */
    function pairXRT(address base, address quote, uint128 xrt) private pure returns (uint128) {
        bool pairOrdered = isPairOrdered(base, quote);
        
        return pairOrdered ? xrt : uint128((ONE**2 / uint256(xrt))); // If pair is not ordered, return the inverse
    }

    function setHash(address base, address quote, uint128 xrt, uint64 when) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(PPF_v1_ID, base, quote, xrt, when));
    }
    
    function isPairOrdered(address base, address quote) private pure returns (bool) {
        return base < quote;
    }
}