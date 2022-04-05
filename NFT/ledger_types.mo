import Text "mo:base/Text";

module {
    public type AccountIdentifier = Text;
    public type SubAccount = [Nat8];
    public type BlockHeight = Nat64;
    

    public type ICPTs = {
        e8s : Nat64;
    };

    public type TokenBlob = {
        id: Nat;
        data: Blob;
        contentType: Text;
    };

    public type TokenData = {
        id: Nat;
        data: [Nat8];
        contentType: Text;
    };
        
    public type Memo = Nat64;

    public type TimeStamp = {
        timestamp_nanos: Nat64;
    };

    public type GetBalanceArgs = {
          account: Text;
    };
    public type SendArgs = {
        memo: Memo;
        amount: ICPTs;
        fee: ICPTs;
        from_subaccount: ?SubAccount;
        to: AccountIdentifier;
        created_at_time: ?TimeStamp;
    };
};