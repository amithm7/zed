use client::Client;
use futures::channel::oneshot;
use gpui::{App, Global, TestAppContext};
use language::language_settings::AllLanguageSettings;
use project::Project;
use semantic_index::FakeEmbeddingProvider;
use semantic_index::SemanticIndex;
use settings::SettingsStore;
use std::{path::Path, sync::Arc};
use tempfile::tempdir;
use util::http::HttpClientWithUrl;

pub fn init_test(cx: &mut TestAppContext) {
    _ = cx.update(|cx| {
        let store = SettingsStore::test(cx);
        cx.set_global(store);
        language::init(cx);
        Project::init_settings(cx);
        SettingsStore::update(cx, |store, cx| {
            store.update_user_settings::<AllLanguageSettings>(cx, |_| {});
        });
    });
}

fn main() {
    env_logger::init();

    use clock::FakeSystemClock;

    App::new().run(|cx| {
        let store = SettingsStore::test(cx);
        cx.set_global(store);
        language::init(cx);
        Project::init_settings(cx);
        SettingsStore::update(cx, |store, cx| {
            store.update_user_settings::<AllLanguageSettings>(cx, |_| {});
        });

        let clock = Arc::new(FakeSystemClock::default());
        let http = Arc::new(HttpClientWithUrl::new("http://localhost:11434"));

        let client = client::Client::new(clock, http.clone(), cx);
        Client::set_global(client.clone(), cx);

        let temp_dir = tempdir().unwrap();

        let embedding_provider = FakeEmbeddingProvider::new();

        let semantic_index = SemanticIndex::new(
            Path::new("/Users/as-cii/dev/semantic-index-db.mdb"),
            embedding_provider,
            cx,
        );

        cx.spawn(|mut cx| async move {
            let args: Vec<String> = std::env::args().collect();
            if args.len() < 2 {
                eprintln!("Usage: cargo run --example index -p semantic_index -- <project_path>");
                cx.update(|cx| cx.quit()).unwrap(); // Exiting if no path is provided
                return;
            }

            let mut semantic_index = semantic_index.await.unwrap();

            let project_path = Path::new(&args[1]);

            let project = Project::example([project_path], &mut cx).await;

            cx.update(|cx| {
                let language_registry = project.read(cx).languages().clone();
                let node_runtime = project.read(cx).node_runtime().unwrap().clone();
                languages::init(language_registry, node_runtime, cx);
            })
            .unwrap();

            let project_index = cx
                .update(|cx| semantic_index.project_index(project.clone(), cx))
                .unwrap();

            let (tx, rx) = oneshot::channel();
            let mut tx = Some(tx);
            let subscription = cx.update(|cx| {
                cx.subscribe(&project_index, move |_, event, _| {
                    if let Some(tx) = tx.take() {
                        _ = tx.send(event.clone());
                    }
                })
            });

            let t0 = std::time::Instant::now();
            rx.await.expect("no event emitted");
            drop(subscription);
            dbg!(t0.elapsed());
            drop(temp_dir);
            cx.update(|cx| cx.quit()).unwrap();
        })
        .detach();
    });
}
