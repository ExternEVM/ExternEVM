pub trait ConsensusStrategy {
    fn proposer_for_slot(&self, slot: u64) -> String;

    fn is_my_turn(&self, slot: u64, my_address: &str) -> bool {
        self.proposer_for_slot(slot).to_lowercase() == my_address.to_lowercase()
    }

    fn validator_count(&self) -> usize;
}
