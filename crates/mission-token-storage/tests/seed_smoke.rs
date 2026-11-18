use mission_token_storage::{seed, Db};

#[test]
fn demo_seed_populates_every_table() {
    let db = Db::open_in_memory().unwrap();
    seed::demo(&db).expect("le seed de démonstration doit réussir");
    let snap = db.load_snapshot().unwrap();
    assert!(snap.agents.len() >= 5, "agents: {}", snap.agents.len());
    assert!(snap.tasks.len() >= 9, "tasks: {}", snap.tasks.len());
    assert!(snap.providers.len() >= 4);
    assert!(snap.software.len() >= 5);
}
