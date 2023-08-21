use starknet::ContractAddress;
use starknet::SyscallResultTrait;

#[starknet::interface]
trait IERC721<TContractState> {
    fn balance_of(self: @TContractState, address: ContractAddress) -> felt252;
    fn owner_of(self: @TContractState, token_id: u256) -> felt252;
    fn get_approved(self: @TContractState, token_id: u256) -> felt252;
    fn get_name(self: @TContractState) -> felt252;
    fn get_symbol(self: @TContractState) -> felt252;
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn burn(ref self: TContractState, token_id: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, token_id: u256);
    fn transfer_from(ref self: TContractState, _from: ContractAddress, _to: ContractAddress, token_id: u256);
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
}


#[starknet::contract]
mod ERC721 {
    use zeroable::Zeroable;
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::contract_address_const;
    use traits::TryInto;
    use traits::Into;
    use option::OptionTrait;

    #[storage]
    struct Storage {
        name: felt252,
        symbol: felt252,
        _ownerOf: LegacyMap::<u256, felt252>,
        _balanceOf: LegacyMap::<ContractAddress, felt252>,
        _approvals: LegacyMap::<u256, felt252>,
        isApprovedForAll: LegacyMap::<(ContractAddress, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Approval: Approval,
        Transfer: Transfer,
        ApprovalForAll: ApprovalForAll,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        caller: ContractAddress, 
        spender: ContractAddress, 
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        _from: ContractAddress, 
        _to: ContractAddress, 
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        caller: ContractAddress, 
        operator: ContractAddress, 
        approved: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState, _name: felt252, _symbol: felt252) {
        self.name.write(_name);
        self.symbol.write(_symbol);
    }

    #[external(v0)]
    impl ERC721_Impl of super::IERC721<ContractState> {
        fn get_name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn get_symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }
        
        fn balance_of(self: @ContractState, address: ContractAddress) -> felt252 {
            self._balanceOf.read(address)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> felt252 {
            let owner = self._ownerOf.read(token_id);
            assert(!owner.is_zero(), 'ERC721: address is Zero');
            owner
        }
        
        fn get_approved(self: @ContractState, token_id: u256) -> felt252 {
            let token = self._ownerOf.read(token_id);
            assert(!token.is_zero(), 'ERC721: token does not exist');
            self._approvals.read(token_id)
        }

        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self._mint(to, token_id);
        }

        fn burn(ref self: ContractState, token_id: u256) {
            assert(self._ownerOf.read(token_id) == get_caller_address().into(), 'ERC721: not authorized');
            self._burn(token_id);
        }

        fn approve(ref self: ContractState, spender: ContractAddress, token_id: u256) {
            let caller = get_caller_address();
            let owner = self._ownerOf.read(token_id);
            assert(caller.into() == owner || self.isApprovedForAll.read((owner.try_into().unwrap(), caller)), 'ERC721: not authorized');

            self._approvals.write(token_id, spender.into());
            self.emit(Approval {caller, spender, token_id, });
        }

        fn transfer_from(ref self: ContractState, _from: ContractAddress, _to: ContractAddress, token_id: u256) {
            let caller = get_caller_address(); 
            assert(_from.into() == self._ownerOf.read(token_id), 'ERC721: from != owner');
            assert(!_to.is_zero(), 'ERC721: to is Zero');
            // assert(IERC721::isApprovedOrOwner(caller, _to, token_id), 'ERC721: not authorized');

            self._balanceOf.write(_from, self._balanceOf.read(_from) - 1);
            self._balanceOf.write(_to, self._balanceOf.read(_to) + 1);
            self._ownerOf.write(token_id, _to.into());

            self._approvals.write(token_id, 0);
            self.emit(Transfer{ _from, _to, token_id, });
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let caller = get_caller_address();
            self.isApprovedForAll.write((caller, operator), approved);
            self.emit(ApprovalForAll{ caller, operator, approved, });
        }


    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            assert(!to.is_zero(), 'ERC721: to is Zero');
            assert(self._ownerOf.read(token_id).is_zero(), 'ERC721: token already exists');

            self._balanceOf.write(to, self._balanceOf.read(to) + 1);
            self._ownerOf.write(token_id, to.into());

            self.emit(Transfer{ _from: contract_address_const::<0>(), _to: to, token_id, });
        }
        
        fn isApprovedOrOwner(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, token_id: u256) -> bool {
            spender == owner || 
                self.isApprovedForAll.read((owner, spender)) ||
                spender.into() == self._approvals.read(token_id)  
        }

        fn _burn(ref self: ContractState, token_id: u256) {
            let owner_as_felt252 = self._ownerOf.read(token_id);
            let owner = owner_as_felt252.try_into().unwrap();
            assert(!owner.is_zero(), 'ERC721: token does not exist');

            self._balanceOf.write(owner, self._balanceOf.read(owner) - 1);
            
            self._ownerOf.write(token_id, 0);
            self._approvals.write(token_id, 0);

            self.emit(Transfer{ _from: owner, _to: contract_address_const::<0>(), token_id, });
        }
    }
}
