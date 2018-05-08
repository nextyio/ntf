pragma solidity ^0.4.21;

import "./StandardToken.sol";
import "../../math/SafeMath.sol";
import "../../ownership/Blacklist.sol";


/**
 * @title Standard Suspendable Token
 * @dev Suspendable basic version of StandardToken, with no allowances.
 */
contract StandardSuspendableToken is StandardToken, Blacklist {
  using SafeMath for uint256;

  bytes32 constant ZERO_TX = 0x0000000000000000000000000000000000000000000000000000000000000000;

  struct Transaction {
    bytes32 txId;
    address from;
    address to;
    uint256 amount;
  }

  mapping(address => uint256) balances;
  mapping(address => Transaction[]) pendingTransfers;
  mapping(address => Transaction[]) pendingReceives;
  mapping(address => bytes32[]) pendingSendTnx;
  mapping(address => bytes32[]) pendingReceiveTnx;

  uint256 totalSupply_;

  event TransferCancelled(address _from, address _to, uint256 _value);
  event TransferConfirmed(bytes32 _txId, address _to);
  event PendingTransfer(address _from, address _to, uint256 _value);

  /**
  * @dev total number of tokens in existence
  */
  function totalSupply() public view returns (uint256) {
    return totalSupply_;
  }

  /**
  * @dev Transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(_to != address(0x0));
    require(_value <= balances[msg.sender]);
    require(balances[_to] + _value >= balances[_to]);

    if (msg.sender == owner) {
      balances[msg.sender] = balances[msg.sender].sub(_value);
      balances[_to] = balances[_to].add(_value);
      emit Transfer(msg.sender, _to, _value);
      return true;
    }

    bytes32 _txId = keccak256(msg.sender, _to, _value, block.timestamp, block.difficulty);
    pendingTransfers[msg.sender].push(Transaction({
      txId: _txId,
      from: msg.sender,
      to: _to,
      amount: _value
    }));
    pendingSendTnx[msg.sender].push(_txId);
    pendingReceives[_to].push(Transaction({
      txId: _txId,
      from: msg.sender,
      to: _to,
      amount: _value
    }));
    pendingReceiveTnx[_to].push(_txId);
    emit PendingTransfer(msg.sender, _to, _value);
    return true;
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);

    if (msg.sender == owner) {
      balances[_from] = balances[_from].sub(_value);
      balances[_to] = balances[_to].add(_value);
      allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
      emit Transfer(_from, _to, _value);
      return true;
    }

    bytes32 _txId = keccak256(_from, _to, _value, block.timestamp, block.difficulty);
    pendingTransfers[_from].push(Transaction({
      txId: _txId,
      from: _from,
      to: _to,
      amount: _value
    }));
    pendingSendTnx[msg.sender].push(_txId);
    pendingReceives[_to].push(Transaction({
      txId: _txId,
      from: _from,
      to: _to,
      amount: _value
    }));
    pendingReceiveTnx[_to].push(_txId);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Cancel pending transfer for a specified transaction id
   * @param _txId The transaction id to be cancelled.
   */
  function cancelTransfer(bytes32 _txId) public returns (bool) {
    require(_txId != ZERO_TX);
    uint length = pendingTransfers[msg.sender].length;
    for (uint i = 0; i < length; i++) {
      Transaction memory transaction;
      transaction = pendingTransfers[msg.sender][i];
      if (_txId == transaction.txId && msg.sender == transaction.from) {
        pendingTransfers[msg.sender][i] = pendingTransfers[msg.sender][length - 1];
        pendingSendTnx[msg.sender][i] = pendingSendTnx[msg.sender][length - 1];
        pendingTransfers[msg.sender].length--;
        pendingSendTnx[msg.sender].length--;
        uint len = pendingReceives[transaction.to].length;
        for (uint k = 0; k < len; k++) {
          Transaction memory tnx;
          tnx = pendingReceives[transaction.to][k];
          if (_txId == tnx.txId && transaction.to == tnx.to) {
            pendingReceives[transaction.to][k] = pendingReceives[transaction.to][len - 1];
            pendingReceiveTnx[transaction.to][k] = pendingReceiveTnx[transaction.to][len - 1];
            pendingReceives[transaction.to].length--;
            pendingReceiveTnx[transaction.to].length--;
            break;
          }
        }
        emit TransferCancelled(msg.sender, transaction.to, transaction.amount);
        return true;
      }
    }
    return false;
  }

  /**
   * @dev confirm pending transaction to perform token transfer
   * @param _txId The transaction id to confirm.
   */
  function confirmTransfer(bytes32 _txId) public returns (bool) {
    require(_txId != ZERO_TX);
    emit TransferConfirmed(_txId, msg.sender);
    uint length = pendingReceives[msg.sender].length;
    for (uint i = 0; i < length; i++) {
      Transaction memory transaction;
      transaction = pendingReceives[msg.sender][i];
      if (_txId == transaction.txId && msg.sender == transaction.to) {
        if (transaction.to == address(0x0)) {
            revert();
        }
        if (transaction.amount > balances[transaction.from]) {
            revert();
        }
        if (balances[transaction.to] + transaction.amount < balances[transaction.to]) {
            revert();
        }
        balances[transaction.from] = balances[transaction.from].sub(transaction.amount);
        balances[msg.sender] = balances[msg.sender].add(transaction.amount);  
        if (blacklist[transaction.from] && !blacklist[msg.sender]) {
          blacklist[msg.sender] = true;
          keys.push(msg.sender);
        }
        pendingReceives[msg.sender][i] = pendingReceives[msg.sender][length - 1];
        pendingReceiveTnx[msg.sender][i] = pendingReceiveTnx[msg.sender][length - 1];
        pendingReceives[msg.sender].length--;
        pendingReceiveTnx[msg.sender].length--;

        uint len = pendingTransfers[transaction.from].length;
        for (uint k = 0; k < len; k++) {
          Transaction memory tnx;
          tnx = pendingTransfers[transaction.from][k];
          if (_txId == tnx.txId && transaction.from == tnx.from) {
            pendingTransfers[transaction.from][k] = pendingTransfers[transaction.from][len - 1];
            pendingSendTnx[transaction.from][k] = pendingSendTnx[transaction.from][len - 1];
            pendingTransfers[transaction.from].length--;
            pendingSendTnx[transaction.from].length--;
            break;
          }
        }
        emit Transfer(transaction.from, msg.sender, transaction.amount);
        return true;
      }
    }
    return false;
  }

  /**
   * @dev Get all pending transfer transactions of the sender
   */
  function getPendingTransfers() public view returns (bytes32[]) {
    return pendingSendTnx[msg.sender];
  }

  /**
   * @dev Get all pending receive transactions of the sender
   */
  function getPendingReceives() public view returns (bytes32[]) {
    return pendingReceiveTnx[msg.sender];
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) public view returns (uint256) {
    return balances[_owner];
  }

}
