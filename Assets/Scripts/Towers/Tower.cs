using UnityEngine;
using System.Collections.Generic;

public class Tower : MonoBehaviour
{
    [Header("타워 기본 설정")]
    public string towerName;
    public int cost;
    public float range = 5f;
    public float fireRate = 1f;
    public int damage = 10;
    public int upgradeCost = 50;
    public int maxLevel = 3;

    [Header("현재 상태")]
    public int level = 1;
    public float currentFireRate;
    private float fireCountdown = 0f;

    [Header("타겟팅")]
    public Transform target;
    public Transform partToRotate;
    public float turnSpeed = 10f;

    [Header("발사체")]
    public GameObject projectilePrefab;
    public Transform firePoint;

    private void Start()
    {
        currentFireRate = fireRate;
        InvokeRepeating("UpdateTarget", 0f, 0.5f);
    }

    private void Update()
    {
        if (target == null)
            return;

        // 타겟을 향해 회전
        Vector3 dir = target.position - transform.position;
        Quaternion lookRotation = Quaternion.LookRotation(dir);
        Vector3 rotation = Quaternion.Lerp(partToRotate.rotation, lookRotation, Time.deltaTime * turnSpeed).eulerAngles;
        partToRotate.rotation = Quaternion.Euler(0f, rotation.y, 0f);

        // 발사 로직
        if (fireCountdown <= 0f)
        {
            Shoot();
            fireCountdown = 1f / currentFireRate;
        }

        fireCountdown -= Time.deltaTime;
    }

    private void UpdateTarget()
    {
        GameObject[] enemies = GameObject.FindGameObjectsWithTag("Enemy");
        float shortestDistance = Mathf.Infinity;
        GameObject nearestEnemy = null;

        foreach (GameObject enemy in enemies)
        {
            float distanceToEnemy = Vector3.Distance(transform.position, enemy.transform.position);
            if (distanceToEnemy < shortestDistance && distanceToEnemy <= range)
            {
                shortestDistance = distanceToEnemy;
                nearestEnemy = enemy;
            }
        }

        if (nearestEnemy != null)
        {
            target = nearestEnemy.transform;
        }
        else
        {
            target = null;
        }
    }

    private void Shoot()
    {
        GameObject projectileGO = Instantiate(projectilePrefab, firePoint.position, firePoint.rotation);
        Projectile projectile = projectileGO.GetComponent<Projectile>();

        if (projectile != null)
        {
            projectile.Seek(target, damage);
        }
    }

    public bool Upgrade()
    {
        if (level >= maxLevel)
            return false;

        if (GameManager.Instance.SpendGold(upgradeCost))
        {
            level++;
            damage += 5;
            range += 1f;
            currentFireRate += 0.2f;
            upgradeCost *= 2;
            return true;
        }
        return false;
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.red;
        Gizmos.DrawWireSphere(transform.position, range);
    }
} 