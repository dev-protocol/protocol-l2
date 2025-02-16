# Payment Splitting

## How to calculate the withdrawable amount.

The following is explanation the concept of calculating the amount of tokens a user can withdraw (=`payment`) using pseudocode in JS syntax.

ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/finance/PaymentSplitter.sol

```javascript!
const total_released_tokens = new Map([['TOKEN', 0]]);
const released_tokens_of_user = new Map([['TOKEN', new Map([['USER', 0]])]]);

function withdraw(token, user) {
    const Property = ERC20(property);
    const Token = ERC20(token);
    const total_received = 
          Token.balanceOf(address(this)) +
          total_released_tokens.get(token);

    /*
     */
    const released = released_tokens_of_user.get(token).get(user);

    const user_balance = Property.balanceOf(user);
    const total_supply = Property.totalSupply();
    const payment = 
        (total_received * user_balance) / total_supply - released;

    /*
     * (TRANSFER TOKENS TO THE USER HERE...)
     */
    ERC20.safeTransfer(token, user, payment);

    /*
     * Update the global states.
     */
    released_tokens_of_user.get(token).set(user, released + payment)
    total_released_tokens.set(
        token,
        total_released_tokens.get(token) + payment
    );

    return payment;
}
```

## Cases

The withdrawable amount is calculated from the latest share of Property.

### Case-1
|_timeline_|_event_|Alice|Bob|Locked Value|
|---|---|---|---|---|
|1||50%|50%|0|
|2|+©100|50%|50%|100|
|3|Alice 20% → Bob|30%|70%|100|
|4|Alice withdraws<br/>Alice earns ©30|30%|70%|70|
|5|Bob withdraws<br/>Bob earns ©70|30%|70%|0|

### Case-2
|_timeline_|_event_|Alice|Bob|Locked Value|
|---|---|---|---|---|
|1||50%|50%|0|
|2|+©100|50%|50%|100|
|3|Alice withdraws<br/>Alice earns ©50|50%|50%|50|
|4|Alice 20% → Bob|30%|70%|50|
|5|+©200|30％|70%|250|
|6|Bob withdraws<br/>Bob earns ©210|30%|70%|40|
|7|Alice withdraws<br/>Alice earns ©40|30%|70%|0|

---

# Idea

ref: https://github.com/dev-protocol/protocol-v2/pull/714

### Vault side

Add a call for updating `released` and a local state that records the user balance at the time of the last withdraw.

```diff
const total_released_tokens = new Map([['TOKEN', 0]]);
const released_tokens_of_user = new Map([['TOKEN', new Map([['USER', 0]])]]);
+ const last_balance_of_user_for_tokens = new Map([['TOKEN', new Map([['USER', 0]])]]);

function withdraw(token, user) {
    const Property = ERC20(property);
    const Token = ERC20(token);
    const total_received = 
          Token.balanceOf(address(this)) +
          total_released_tokens.get(token);

+   updateReleasedTokens(token, user, Property.balanceOf(user));
    
    /*
     */
    const released = released_tokens_of_user.get(token).get(user);

    const user_balance = Property.balanceOf(user);
    const total_supply = Property.totalSupply();
    const payment = 
        (total_received * user_balance) / total_supply - released;

    /*
     * (TRANSFER TOKENS TO THE USER HERE...)
     */
    ERC20.safeTransfer(token, user, payment);

    /*
     * Update the global states.
     */
    released_tokens_of_user.get(token).set(user, released + payment)
    total_released_tokens.set(
        token,
        total_released_tokens.get(token) + payment
    );
    
+   last_balance_of_user_for_tokens[token][user] = user_balance;

    return payment;
}
```

`updateReleasedTokens` updates the value of `released` by referencing `Withdraw.transferHistory` recursively until `last_balance_of_user_for_tokens` matches the latest balance.

```javascript!
const released_tokens_addresses = new Map([['USER', new Set()]]); // mapping(address => EnumerableSet.AddressSet)
const Withdraw = Withdraw(Registry(registry).registries('Withdraw'));

function updateReleasedTokens(token, user, current_balance) {
    if (last_balance_of_user_for_tokens[token][user] === current_balance) {
        // No need to update it.
        return
    }

    const historyIndex = Withdraw.transferHistoryLengthOfRecipient(address(Property), user);
    let done = false;
    let i = historyIndex;
    let calculated = 0;
    while (!done || i >= 0) {
        const history = Withdraw.transferHistory(
            Withdraw.transferHistoryOfRecipientByIndex(i)
        );
        if (!history.fill) {
            // This is always done on the history of the last 1 transfer, and other case, history.fill is true.
            history.amount = current_balance - history.preBalanceOfRecipient;
        }

        updateReleasedTokens(token, history.from, Property.balanceOf(history.from));

        const released_tokens = released_tokens_of_user.get(token).get(history.from);
        const part_of_released = released_tokens * history.preBalanceOfSender / history.amount;
        released_tokens_of_user.get(token).set(
            user,
            part_of_released + released_tokens_of_user.get(token).get(user)
        );
        
        i = i - 1;
        calculated = calculated + history.amount;
        done = last_balance_of_user_for_tokens[token][user] + calculated === current_balance;
    }
}
```

