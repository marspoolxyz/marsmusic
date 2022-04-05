/**

 */
import Text "mo:base/Text";
import Result "mo:base/Result";
import ExtCore "./Core";
module ExtNonFungible = {
  public type MintRequest = {
    to : ExtCore.User;
    metadata : ?Blob;
  };

  /*
      _metaData.put(_claimTokenId, receiver);
    _rarity.put(_claimTokenId, receiver);
    _account.put(_claimTokenId, receiver);
    _amountPaid.put(_claimTokenId, receiver);
    _blockHeight.put(_claimTokenId, receiver);
  */
  public type ClaimRequest = {
    metadata : Text;
    rarity : Text;
    account : Text;
    amountPaid : Nat64;
    blockHeight : Nat64;
  };  
  public type Service = actor {
    bearer: query (token : ExtCore.TokenIdentifier) -> async Result.Result<ExtCore.AccountIdentifier, ExtCore.CommonError>;

    mintNFT: shared (request : MintRequest) -> async ();
  };
};
