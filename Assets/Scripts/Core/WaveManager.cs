using UnityEngine;
using System.Collections;

public class WaveManager : MonoBehaviour
{
    [System.Serializable]
    public class Wave
    {
        public GameObject enemyPrefab;
        public int count;
        public float spawnRate;
    }

    public Wave[] waves;
    public Transform spawnPoint;
    public float timeBetweenWaves = 5f;

    private int currentWaveIndex = 0;
    private bool isSpawning = false;

    private void Start()
    {
        StartCoroutine(StartNextWave());
    }

    private IEnumerator StartNextWave()
    {
        if (currentWaveIndex < waves.Length)
        {
            Wave wave = waves[currentWaveIndex];
            isSpawning = true;

            for (int i = 0; i < wave.count; i++)
            {
                SpawnEnemy(wave.enemyPrefab);
                yield return new WaitForSeconds(1f / wave.spawnRate);
            }

            isSpawning = false;
            currentWaveIndex++;

            yield return new WaitForSeconds(timeBetweenWaves);
            StartCoroutine(StartNextWave());
        }
        else
        {
            // 모든 웨이브 완료
            Debug.Log("모든 웨이브 완료!");
        }
    }

    private void SpawnEnemy(GameObject enemyPrefab)
    {
        Instantiate(enemyPrefab, spawnPoint.position, spawnPoint.rotation);
    }

    public bool IsWaveInProgress()
    {
        return isSpawning;
    }

    public int GetCurrentWave()
    {
        return currentWaveIndex + 1;
    }

    public int GetTotalWaves()
    {
        return waves.Length;
    }
} 