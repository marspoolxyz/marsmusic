/*
ERC721 - note the following:
-No notifications (can be added)
-All tokenids are ignored
-You can use the canister address as the token id
-Memo is ignored
-No transferFrom (as transfer includes a from field)
*/
import Cycles "mo:base/ExperimentalCycles";
import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Iter "mo:base/Iter";
import AID "../motoko/util/AccountIdentifier";
import ExtCore "../motoko/ext/Core";
import ExtCommon "../motoko/ext/Common";
import ExtAllowance "../motoko/ext/Allowance";
import ExtNonFungible "../motoko/ext/NonFungible";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Hex "../motoko/util/Hex";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Ledger "./ledger_types";
import Option "mo:base/Option";
import Bool "mo:base/Bool";

shared (install) actor class musicNFT(init_minter: Principal) = this {
  
  // Types
  type AccountIdentifier = ExtCore.AccountIdentifier;
  type SubAccount = ExtCore.SubAccount;
  type User = ExtCore.User;
  type Balance = ExtCore.Balance;
  type TokenIdentifier = ExtCore.TokenIdentifier;
  type TokenIndex  = ExtCore.TokenIndex ;
  type Extension = ExtCore.Extension;
  type CommonError = ExtCore.CommonError;
  type BalanceRequest = ExtCore.BalanceRequest;
  type BalanceResponse = ExtCore.BalanceResponse;
  type TransferRequest = ExtCore.TransferRequest;
  type TransferResponse = ExtCore.TransferResponse;
  type AllowanceRequest = ExtAllowance.AllowanceRequest;
  type ApproveRequest = ExtAllowance.ApproveRequest;
  type Metadata = ExtCommon.Metadata;
  type MintRequest  = ExtNonFungible.MintRequest ;
  type ClaimRequest  = ExtNonFungible.ClaimRequest ;
  type TokenStatistics  = ExtCore.TokenStatistics;

  type TokenBlob = Ledger.TokenBlob;
  type TokenData = Ledger.TokenData;


  type HeaderField = (Text, Text);
  type HttpResponse = {
    status_code: Nat16;
    headers: [HeaderField];
    body: Blob;
  };  
  type HttpRequest = {
    method : Text;
    url : Text;
    headers : [HeaderField];
    body : Blob;
  };
  let NOT_FOUND : HttpResponse = {status_code = 404; headers = []; body = Blob.fromArray([]); streaming_strategy = null};
  let BAD_REQUEST : HttpResponse = {status_code = 400; headers = []; body = Blob.fromArray([]); streaming_strategy = null};

  private var isLocal : Bool = false;                      // ***********

  private let EXTENSIONS : [Extension] = ["@ext/common", "@ext/allowance", "@ext/nonfungible"];
  
  //State work
  private stable var _registryState : [(TokenIndex, AccountIdentifier)] = [];
  private var _registry : HashMap.HashMap<TokenIndex, AccountIdentifier> = HashMap.fromIter(_registryState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
	
  private stable var _allowancesState : [(TokenIndex, Principal)] = [];
  private var _allowances : HashMap.HashMap<TokenIndex, Principal> = HashMap.fromIter(_allowancesState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
	
	private stable var _tokenMetadataState : [(TokenIndex, Metadata)] = [];
  private var _tokenMetadata : HashMap.HashMap<TokenIndex, Metadata> = HashMap.fromIter(_tokenMetadataState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
  
  private stable var _holderState : [(TokenIndex, AccountIdentifier)] = [];
  private var _holders : HashMap.HashMap<TokenIndex, AccountIdentifier> = HashMap.fromIter(_holderState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);

  func isEqP(x: Principal, y: Principal): Bool { x == y };
  func isEq(x: Nat, y: Nat): Bool { x == y };

  private stable var _owners : [(Text, [TokenIndex])] = []; 
  private var owners_ : HashMap.HashMap<Text, [TokenIndex]> = HashMap.fromIter(_owners.vals(), 0, Text.equal,  Text.hash);
  var debugMessage :Text = "";


  private stable var _metaDataState : [(TokenIndex, Text)] = [];
  private var _metaData : HashMap.HashMap<TokenIndex, Text> = HashMap.fromIter(_metaDataState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);

  private stable var _rarityState : [(TokenIndex, Text)] = [];
  private var  _rarity : HashMap.HashMap<TokenIndex, Text> = HashMap.fromIter(_rarityState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);


  private stable var _amountPaidState : [(TokenIndex, Nat64)] = [];
  private var _amountPaid : HashMap.HashMap<TokenIndex, Nat64> = HashMap.fromIter(_amountPaidState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);

  private stable var _blockHeightState : [(Nat,TokenIndex)] = [];
  private var _blockHeight : HashMap.HashMap<Nat,TokenIndex> = HashMap.fromIter(_blockHeightState.vals(), 0, isEq, Nat32.fromNat);


  private stable var _accountState : [(Text, TokenIndex)] = [];
  private var _account : HashMap.HashMap<Text, TokenIndex> = HashMap.fromIter(_accountState.vals(), 0, Text.equal,  Text.hash);

  private stable var maxSupply_ : Balance  = 10000;

  private stable var _supply : Balance  = 0;
  private stable var _claim : Balance  = 0;

  private stable var _minter : Principal  = init_minter;
  private stable var _nextTokenId : TokenIndex  = 0;
  private stable var _claimTokenId : TokenIndex  = 0;

  let limit = 50_000_000_000_000;
  public type AccountBalanceArgs = { account : LedgerAccountIdentifier };
  public type LedgerAccountIdentifier = Text;
  type ICPTs = { e8s : Nat64 };
  public type CanisterId = Principal;

  private var assetMap_ = HashMap.HashMap<Text, TokenBlob>(maxSupply_, Text.equal, Text.hash);
  stable var _assetMap : [(Text, TokenBlob)] = [];   

  private var walletsAllowed_ = HashMap.HashMap<Principal, Nat>(maxSupply_, isEqP,  Principal.hash);
  stable var _walletsAllowed : [(Principal, Nat)] = [];
  
  private stable var mintedToken : Nat = 0;

  let LedgerCanister  = actor "ryjl3-tyaaa-aaaaa-aaaba-cai" : actor { 
      send_dfx: (args : Ledger.SendArgs) -> async Ledger.BlockHeight;
      account_balance_dfx : shared query AccountBalanceArgs -> async ICPTs;
      get_nodes : shared query () -> async [CanisterId];
  };

  //State functions
  system func preupgrade()
  {
    _registryState := Iter.toArray(_registry.entries());
    _allowancesState := Iter.toArray(_allowances.entries());
    _tokenMetadataState := Iter.toArray(_tokenMetadata.entries());
    _holderState := Iter.toArray(_holders.entries());
    _owners := Iter.toArray(owners_.entries());

    _metaDataState := Iter.toArray(_metaData.entries());
    _rarityState := Iter.toArray(_rarity.entries());
    _accountState := Iter.toArray(_account.entries());
    _amountPaidState := Iter.toArray(_amountPaid.entries());
    _blockHeightState := Iter.toArray(_blockHeight.entries());

    _assetMap := Iter.toArray(assetMap_.entries());
    _walletsAllowed := Iter.toArray(walletsAllowed_.entries());
    
  };

  system func postupgrade() {    
    _registryState := [];
    _allowancesState := [];
    _tokenMetadataState := [];
    _holderState := [];
    _owners := [];

    _metaDataState := [];
    _rarityState   := []; 
    _accountState := [];
    _amountPaidState := [];
    _blockHeightState := [];

    walletsAllowed_ := HashMap.fromIter<Principal, Nat>(_walletsAllowed.vals(),maxSupply_, isEqP,  Principal.hash);
    _walletsAllowed := []; 

    assetMap_ := HashMap.fromIter<Text, TokenBlob>(_assetMap.vals(),maxSupply_, Text.equal,  Text.hash);
    _assetMap := [];    
  };

	public shared(msg) func clear() : async () {
    assert(msg.caller == _minter);

    _registryState := [];
    _allowancesState := [];
    _tokenMetadataState := [];
    _holderState := [];
    _owners := [];

    _metaDataState := [];
    _rarityState   := []; 
    _accountState := [];
    _amountPaidState := [];
    _blockHeightState := [];    

     _registry := HashMap.fromIter(_registryState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    _allowances := HashMap.fromIter(_allowancesState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    _tokenMetadata := HashMap.fromIter(_tokenMetadataState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    _holders := HashMap.fromIter(_holderState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    owners_ := HashMap.fromIter(_owners.vals(), 0, Text.equal,  Text.hash);


    _blockHeight := HashMap.fromIter(_blockHeightState.vals(), 0, isEq,  Nat32.fromNat);
    _amountPaid := HashMap.fromIter(_amountPaidState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    _account := HashMap.fromIter(_accountState.vals(), 0, Text.equal,  Text.hash);
    _rarity := HashMap.fromIter(_rarityState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    _metaData := HashMap.fromIter(_metaDataState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);

    _nextTokenId := 0;
    _claimTokenId := 0;
    _supply := 0;
};

	public shared(msg) func setMinter(minter : Principal) : async () {
		assert(msg.caller == _minter);
		_minter := minter;
	};
	
  public shared(msg) func mintNFT(request : MintRequest) : async TokenIndex {

    //Mint every NFT to the NFT Owner and transfer to the buyer
    //public shared(msg) func mintNFT() : async TokenIndex {
    //let receiver = AID.fromPrincipal(msg.caller, null);

		assert(msg.caller == _minter);
    let receiver = ExtCore.User.toAID(request.to);

    let token = _nextTokenId;
		let md : Metadata = #nonfungible({
			metadata = request.metadata;
		}); 
		_registry.put(token, receiver);

    // Transfer from Null account
    var tokens = owners_.get(receiver);
    switch (tokens) {
        case (?tokens) {
            Debug.print("Appending........"# receiver);
            owners_.put(receiver, Array.append(tokens, [token]));
        };
        case (_) {
            Debug.print("Creating........"# receiver);
            owners_.put(receiver, Array.make(token));
        };
    };

    _allowances.put(token, msg.caller);


		_tokenMetadata.put(token, md);
		_supply := _supply + 1;
		_nextTokenId := _nextTokenId + 1;
    token;
	};

  public query func getTokenStatistics(): async TokenStatistics
  {   
      {
        supply = _supply;
        claimed = _claimTokenId;
        available = _nextTokenId;          
      };        
  };

  public shared(msg) func clearAccounts(accountText : Text) : async Text  {
    assert(msg.caller == _minter);
    _account.delete(accountText);
    accountText;
  };


  public shared(msg) func addWallets(allowWallet: Principal) : async Bool
  {
      assert(msg.caller == _minter);
      walletsAllowed_.put(allowWallet,1);
      return true;
  };  

  private func isWalletAllowed(checkWallet: Principal) : async Bool
  {

      if(checkWallet == _minter) // The Canister Owner
      {
          return true;
      };

      let walletCheck = walletsAllowed_.get(checkWallet);

      switch (walletCheck)
      {
          case (?walletCheck) 
          {
              return true;
          };
          case (_) {
              return false;
          }
      };
  }; 

  //Handling On-Chain minting
  private func saveAsset_(data: TokenData,tokenId: Nat) : async Nat {

      let tokenData = {
          id = tokenId;
          data = Blob.fromArray(data.data); 
          contentType = data.contentType;
      };
      //Store token data asset
      assetMap_.put("/Token/" # Nat.toText(tokenId), tokenData);
      
      maxSupply_ += 1;
    
      return tokenId;
  };
  // On-Chain Mint only the Owner can add images
  public shared(msg) func saveAsset(data: TokenData,tokenId: Nat) : async Nat {
      
      let isAllowed = await isWalletAllowed(msg.caller);
      
      assert(isAllowed == true);
      assert(tokenId >= 0);
      assert(tokenId < maxSupply_);
                
      mintedToken :=  await saveAsset_(data,tokenId);   
      return mintedToken;   
  };  
  /*
    private stable var _accountState : [(Text, TokenIndex)] = [];
  private var _account : HashMap.HashMap<Text, TokenIndex> = HashMap.fromIter(_accountState.vals(), 0, Text.equal,  Text.hash);

  1. MetaData of the NFT  -Save
      1. Circle NFT
      2. Song Text
  2. Paid Account ID  - Save - No Duplicate
  3. Amount Paid - Save
  4. Principal - msg.caller
  5. Rarity Data - Save
  6. BlockHeight
  */
  public shared(msg) func claimNFT(request : ClaimRequest) : async TokenIndex  {

    debugMessage := debugMessage # "\n " # "\n claimNFT ClaimTokenId " # Nat32.toText(_claimTokenId) # " Supply " # Nat32.toText(Nat32.fromNat(_supply));
    debugMessage := debugMessage # "\n " # " Principal ="# Principal.toText(msg.caller);

    var supply_ = Nat32.fromNat(_supply);
     
    if(Nat32.greaterOrEqual(_claimTokenId ,supply_))
    {
      debugMessage := debugMessage # "\n " # "No enough tokens!";
      return 20000;
    };

   // Validate whether the account alreadyexists
    var isAccountExist = _account.get(request.account);
    var AccountExist = false;
    switch (isAccountExist) {
        case (?isAccountExist) {
            AccountExist := true;
         };
        case (_) {
            AccountExist := false
         };
    };     

    if(AccountExist == true)
    {
      debugMessage := debugMessage # "\n " # " Account Identifier already exist " # request.account;
      return 20001;
    };


    // Validate whether the blocksend alreadyexists
    var isBlockHeightExist = _blockHeight.get(Nat64.toNat(request.blockHeight));
    var blockHeightExist = false;
    switch (isBlockHeightExist) {
        case (?isBlockHeightExist) {
            blockHeightExist := true;
         };
        case (_) {
            blockHeightExist := false
         };
    };

    if(blockHeightExist == true)
    {
      debugMessage := debugMessage # "\n " # " Block Height already exist = " # Nat64.toText(request.blockHeight);
      return 20002;
    };

    var balance :Bool = false;
    var compareBool :Bool = false;

    balance := await getAccountBalance(request.account);


    if(Bool.equal(balance,compareBool))
    {
      debugMessage := debugMessage # "\n " # " Zero Balance sent Account ID :"# request.account ;
      return 20003;
    };

    debugMessage := debugMessage # "\n " # " All validation over";
    
    let token = _claimTokenId;
   
    //User has to have map entry, we can just call unsafe unwrap
    //Remove token from current owner
		let receiver = AID.fromPrincipal(msg.caller, null);   
    
    var tokenOwner =  Option.unwrap(_registry.get(token));    
    var tokens = Option.unwrap(owners_.get(tokenOwner));   
    
    owners_.put(tokenOwner, Array.filter<TokenIndex>(tokens, func(x) {x != token}));    
     
    // Transfer from Receiver account
    var receiverTokens = owners_.get(receiver);

    switch (receiverTokens) {
        case (?receiverTokens) {
            Debug.print("Appending........"# receiver);
            owners_.put(receiver, Array.append(receiverTokens, [token]));
        };
        case (_) {
            Debug.print("Creating........"# receiver);
            owners_.put(receiver, Array.make(token));
        };
    };

		_registry.put(_claimTokenId, receiver);
    _allowances.delete(_claimTokenId);    
    _allowances.put(_claimTokenId, msg.caller);
		_holders.put(_claimTokenId, receiver);

    _metaData.put(_claimTokenId, request.metadata);
    _rarity.put(_claimTokenId, request.rarity);
    _amountPaid.put(_claimTokenId, request.amountPaid);

    //Cannot be duplicate
    _account.put(request.account, _claimTokenId);
    _blockHeight.put(Nat64.toNat(request.blockHeight), _claimTokenId);

    debugMessage := debugMessage # "\n " # " NFT Token "# Nat32.toText(_claimTokenId) #" Transfered to Account: " # request.account;
    debugMessage := debugMessage # "\n " # " NFT Paid: " # Nat64.toText(request.amountPaid);

  

		_supply := _supply + 1;
    _claimTokenId := _claimTokenId + 1;

    
    token;
  };


  public query func getAllMetaData(code:Nat) : async [(TokenIndex, Text)]  {

    if(code == 5871)
    {
        Iter.toArray(_metaData.entries());
    }
    else
    {
        _metaDataState;
    };
  };

  public query func getMetaData(tokenIndex:TokenIndex) : async Text  {

        var metaData = _metaData.get(tokenIndex);
        switch (metaData) {
            case (?metaData) {
                metaData;
            };
            case (_) {
                var error = "not available";
                error;
            };
        };
  };   

  public query func getRarity(tokenIndex:TokenIndex) : async Text  {

        var rarity = _rarity.get(tokenIndex);
        switch (rarity) {
            case (?rarity) {
                rarity;
            };
            case (_) {
                var error = "not available";
                error;
            };
        };
  }; 

  public query func getAllRarity(code:Nat) : async [(TokenIndex, Text)]  {
        Iter.toArray(_rarity.entries());
  }; 

  public query func getCanisterPrincipal () : async Principal  {
    Principal.fromActor(this);
  };


  
  public shared(msg) func transfer(request: TransferRequest) : async TransferResponse {
    if (request.amount != 1) {
			return #err(#Other("Must use amount of 1"));
		};

    /*
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(request.token));
		};
    let token = ExtCore.TokenIdentifier.getIndex(request.token);
    */
		let token = request.token;
    let owner = ExtCore.User.toAID(request.from);
    let spender = AID.fromPrincipal(msg.caller, request.subaccount);
    let receiver = ExtCore.User.toAID(request.to);
		
    switch (_registry.get(token)) {
      case (?token_owner) {
				if(AID.equal(owner, token_owner) == false) {
					return #err(#Unauthorized(owner));
				};
				if (AID.equal(owner, spender) == false) {
					switch (_allowances.get(token)) {
						case (?token_spender) {
							if(Principal.equal(msg.caller, token_spender) == false) {								
								return #err(#Unauthorized(spender));
							};
						};
						case (_) {
							return #err(#Unauthorized(spender));
						};
					};
				};

        var tokenOwner =  Option.unwrap(_registry.get(token));
        var tokens = Option.unwrap(owners_.get(tokenOwner));
        owners_.put(tokenOwner, Array.filter<TokenIndex>(tokens, func(x) {x != token}));

        // Transfer from Receiver account
        var receiverTokens = owners_.get(receiver);
        switch (receiverTokens) {
            case (?receiverTokens) {
                Debug.print("Appending........"# receiver);
                owners_.put(receiver, Array.append(receiverTokens, [token]));
            };
            case (_) {
                Debug.print("Creating........"# receiver);
                owners_.put(receiver, Array.make(token));
            };
        };        
        
				_allowances.delete(token);
				_registry.put(token, receiver);
       _allowances.put(token, msg.caller);

				return #ok(request.amount);
      };
      case (_) {
        return #err(#InvalidTokenId(request.token));
      };
    };
  };
  
  public shared(msg) func approve(request: ApproveRequest) : async () {
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return;
		};
		let token = ExtCore.TokenIdentifier.getIndex(request.token);
    let owner = AID.fromPrincipal(msg.caller, request.subaccount);
		switch (_registry.get(token)) {
      case (?token_owner) {
				if(AID.equal(owner, token_owner) == false) {
					return;
				};
				_allowances.put(token, request.spender);
        return;
      };
      case (_) {
        return;
      };
    };
  };

  ///Returns list of tokens owned by given user
  public shared(msg) func wallet_tokens(): async [TokenIndex] {

    	let owner = AID.fromPrincipal(msg.caller, null);    

      var tokens = owners_.get(owner);

      switch (tokens) {
          case (?tokens) {
              return tokens;
          };
          case (_) {
              return [];
          }
      }
  };


  ///Returns list of tokens owned by given principal
  public query func wallet_token(user: Principal): async [TokenIndex] {

    	let owner = AID.fromPrincipal(user, null);    

      var tokens = owners_.get(owner);

      switch (tokens) {
          case (?tokens) {
              return tokens;
          };
          case (_) {
              return [];
          }
      }
  };


  ///Returns list of tokens owned by given user
  public query func user_tokens(request: ExtCore.User): async [TokenIndex] {

      let owner = ExtCore.User.toAID(request);

      var tokens = owners_.get(owner);

      switch (tokens) {
          case (?tokens) {
              return tokens;
          };
          case (_) {
              return [];
          }
      }
  };

  //
  public query func getAccounts(code:Nat) : async [(Text, TokenIndex)]  {
        Iter.toArray(_account.entries());
  };
 
  public query func getOwners(code:Nat) : async [(Text, [TokenIndex])]  {
      
      if(code == 5871)
      {
        Iter.toArray(owners_.entries());
      }
      else
      {
        _owners;
      };
  };   
  public query func getMinter() : async Principal {
    _minter;
  };
  public query func extensions() : async [Extension] {
    EXTENSIONS;
  };
  
  public query func balance(request : BalanceRequest) : async BalanceResponse {
   
    /*
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(request.token));
		};
    let token = ExtCore.TokenIdentifier.getIndex(request.token);
    */
		let token = request.token;
    let aid = ExtCore.User.toAID(request.user);
    Debug.print("I am here..246");
    switch (_registry.get(token)) {
      case (?token_owner) {
				if (AID.equal(aid, token_owner) == true) {
              Debug.print("I am here..250");

					return #ok(1);
				} else {					
              Debug.print("I am here..254");

					return #ok(0);
				};
      };
      case (_) {
            Debug.print("I am here..260");

        return #err(#InvalidTokenId(request.token));
      };
    };
  };
	
	public query func allowance(request : AllowanceRequest) : async Result.Result<Balance, CommonError> {
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(request.token));
		};
		let token = ExtCore.TokenIdentifier.getIndex(request.token);
		let owner = ExtCore.User.toAID(request.owner);
		switch (_registry.get(token)) {
      case (?token_owner) {
				if (AID.equal(owner, token_owner) == false) {					
					return #err(#Other("Invalid owner"));
				};
				switch (_allowances.get(token)) {
					case (?token_spender) {
						if (Principal.equal(request.spender, token_spender) == true) {
							return #ok(1);
						} else {					
							return #ok(0);
						};
					};
					case (_) {
						return #ok(0);
					};
				};
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };
  
	public query func bearer(token : TokenIndex) : async Result.Result<AccountIdentifier, CommonError> {
    /*
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(request.token));
		};
    let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    */
		let tokenind = token;
   
    switch (_registry.get(tokenind)) {
      case (?token_owner) {
				return #ok(token_owner);
      };
      case (_) {
        return #err(#InvalidTokenId(token));
      };
    };
	};
  
	public query func supply() : async Result.Result<Balance, CommonError> {
    #ok(_supply);
  };
  
  public query func getRegistry() : async [(TokenIndex, AccountIdentifier)] {
    Iter.toArray(_registry.entries());
  };
  public query func getAllowances() : async [(TokenIndex, Principal)] {
    Iter.toArray(_allowances.entries());
  };
  public query func getTokens() : async [(TokenIndex, Metadata)] {
    Iter.toArray(_tokenMetadata.entries());
  };
  
  public query func metadata(token : TokenIdentifier) : async Result.Result<Metadata, CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(token));
		};
		let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    switch (_tokenMetadata.get(tokenind)) {
      case (?token_metadata) {
				return #ok(token_metadata);
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };


  private func getAccountBalance(accountID:Text) : async Bool {

      var balance : Ledger.ICPTs = {e8s = 0};
      var price  : Nat64 = 10000;

      var fact :Bool = true;
      var not_fact :Bool = false;

      if(isLocal == fact)
      {
          balance := {e8s = 35_000_000};
          
      }
      else
      {
          balance := await LedgerCanister.account_balance_dfx({
            account = accountID;
            });
      };

      if(Nat64.less(balance.e8s, price))
      {
        return not_fact;
      }
      else
      {
        return fact;
      };
  };

  public shared(msg) func resetDebug() : async Text {
      assert(msg.caller == _minter);
      debugMessage := "";
      return "Debug cleared!";
  };      
  public query func getDebug() : async Text {
    debugMessage;
  };  
  
  //Internal cycle management - good general case
  public func acceptCycles() : async () {
    let available = Cycles.available();
    let accepted = Cycles.accept(available);
    assert (accepted == available);
  };
  public query func availableCycles() : async Nat {
    return Cycles.balance();
  };
  public func wallet_receive() : async { accepted: Nat64 } 
  {
      let available = Cycles.available();
      let accepted = Cycles.accept(Nat.min(available, limit));
      { accepted = Nat64.fromNat(accepted) };
  };  

   public query func http_request(request: HttpRequest) : async HttpResponse {

        Debug.print(request.url);
        var holders: Nat = 0;

        let path = Iter.toArray(Text.tokens(request.url, #text("/")));
        
        var response_code: Nat16 = 200;
        var body = Blob.fromArray([]);
        var headers: [(Text, Text)] = [];

        if (path.size() == 0) {
            
          response_code := 200;
          headers := [("content-type", "text/plain")];
          body := Text.encodeUtf8 (
            "Trillion Balance:                          " # debug_show (Cycles.balance()/1000000000000) # "T\n" #
            "Cycle Balance:                             " # debug_show (Cycles.balance()) # "Cycles\n" #
            "Total Supply:                              " # debug_show (maxSupply_) #"\n" #
            "Owner Principal:                           " # Principal.toText(_minter) # "\n" #
            "Current NFT Size:                          " # Nat.toText(assetMap_.size()) # "\n" #
             "Debug Message:                             " # debugMessage # "\n"  
          );

        } else {

     
            let asset = assetMap_.get(request.url);
            
            switch (asset) {
                case (?asset) {

                    //body := Blob.fromArray(asset.data);
                    body := asset.data;
                    headers := [("Content-Type", asset.contentType)];
                };
                case (_) {
                    response_code := 404;
                }
            };                 

            if(response_code == 404)
            {

                response_code := 201;
            };
        };

        return {
            body = body;
            headers = headers;
            status_code = response_code;
            streaming_strategy = null;
        };
    };

}
