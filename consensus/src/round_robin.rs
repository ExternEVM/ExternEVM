use crate::consensus::ConsensusStrategy;

pub struct RoundRobin {
    validators: Vec<String>,
}

impl RoundRobin {
    pub fn new(validators: Vec<String>) -> Self {
        assert!(!validators.is_empty(), "Validator set cannot be empty");
        let validators = validators.iter().map(|v| v.to_lowercase()).collect();
        Self { validators }
    }
}

impl ConsensusStrategy for RoundRobin {
    fn proposer_for_slot(&self, slot: u64) -> String {
        let idx = (slot as usize) % self.validators.len();
        self.validators[idx].clone()
    }

    fn validator_count(&self) -> usize {
        self.validators.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_round_robin_rotation() {
        let rr = RoundRobin::new(vec![
            "0xaaaa".to_string(),
            "0xbbbb".to_string(),
            "0xcccc".to_string(),
        ]);
        assert_eq!(rr.proposer_for_slot(0), "0xaaaa");
        assert_eq!(rr.proposer_for_slot(1), "0xbbbb");
        assert_eq!(rr.proposer_for_slot(2), "0xcccc");
        assert_eq!(rr.proposer_for_slot(3), "0xaaaa");
    }

    #[test]
    fn test_is_my_turn() {
        let rr = RoundRobin::new(vec!["0xAAAA".to_string(), "0xBBBB".to_string()]);
        assert!(rr.is_my_turn(0, "0xaaaa"));
        assert!(!rr.is_my_turn(0, "0xbbbb"));
        assert!(rr.is_my_turn(1, "0xbbbb"));
    }
}
