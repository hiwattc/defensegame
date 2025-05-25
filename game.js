const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

// 게임 상수
const UNIT_TYPES = {
    melee: { health: 100, damage: 20, speed: 2, range: 30, cooldown: 2000, emoji: '🦸‍♂️' },
    archer: { health: 80, damage: 15, speed: 1.5, range: 150, cooldown: 3000, emoji: '👮‍♂️' },
    cannon: { health: 120, damage: 40, speed: 1, range: 200, cooldown: 5000, emoji: '🚜' }
};

// 게임 상태
let units = [];
let enemyUnits = [];
let projectiles = [];
let explosions = [];
let watchTowers = [];  // 와치타워 배열 추가
let rocks = [];  // 바위 배열 추가
let craters = [];  // 크레이터 배열 추가
let lastSpawnTime = { melee: 0, archer: 0, cannon: 0 };
let gameLoop;
let isGameOver = false;
let playerCastle;
let enemyCastle;
let enemyPowerMultiplier = 1;  // 적 공격력 배율

// 성 클래스
class Castle {
    constructor(x, isEnemy = false) {
        this.x = x;
        this.y = canvas.height / 2;
        this.width = 60;
        this.height = 100;
        this.health = 1000;
        this.maxHealth = 1000;
        this.isEnemy = isEnemy;
        this.isDestroyed = false;
    }

    draw() {
        // 성 그리기
        ctx.fillStyle = this.isEnemy ? '#ff0000' : '#0000ff';
        ctx.fillRect(this.x - this.width/2, this.y - this.height/2, this.width, this.height);
        
        // 성 이모티콘
        ctx.font = '40px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('🏰', this.x, this.y);

        // 체력바 그리기
        const healthBarWidth = this.width;
        const healthBarHeight = 10;
        const healthPercentage = this.health / this.maxHealth;
        
        ctx.fillStyle = '#ff0000';
        ctx.fillRect(this.x - healthBarWidth/2, this.y - this.height/2 - 20, healthBarWidth, healthBarHeight);
        ctx.fillStyle = '#00ff00';
        ctx.fillRect(this.x - healthBarWidth/2, this.y - this.height/2 - 20, healthBarWidth * healthPercentage, healthBarHeight);

        // 체력 수치 표시
        ctx.fillStyle = '#ffffff';
        ctx.font = '12px Arial';
        ctx.fillText(`${Math.ceil(this.health)}/${this.maxHealth}`, this.x, this.y - this.height/2 - 25);
    }

    takeDamage(damage) {
        if (this.isDestroyed) return;
        
        this.health -= damage;
        if (this.health <= 0) {
            this.health = 0;
            this.isDestroyed = true;
            gameOver(!this.isEnemy);
        }
    }
}

// 발사체 클래스
class Projectile {
    constructor(x, y, targetX, targetY, speed, damage, size, isEnemy) {
        this.x = x;
        this.y = y;
        this.targetX = targetX;
        this.targetY = targetY;
        this.speed = speed;
        this.damage = damage;
        this.size = size;
        this.isEnemy = isEnemy;
        
        // 발사체 방향 계산
        const dx = targetX - x;
        const dy = targetY - y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        this.vx = (dx / distance) * speed;
        this.vy = (dy / distance) * speed;
    }

    update() {
        this.x += this.vx;
        this.y += this.vy;
    }

    draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
        ctx.fillStyle = this.isEnemy ? '#ff0000' : '#0000ff';
        ctx.fill();
    }

    isOutOfBounds() {
        return this.x < 0 || this.x > canvas.width || this.y < 0 || this.y > canvas.height;
    }
}

// 크레이터 클래스
class Crater {
    constructor(x, y, size) {
        this.x = x;
        this.y = y;
        this.size = size;
        this.emoji = '🕳️';
    }

    draw() {
        ctx.font = `${this.size}px Arial`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(this.emoji, this.x, this.y);
    }

    // 유닛이 크레이터 위에 있는지 확인
    isUnitInCrater(unitX, unitY, unitRadius) {
        const dx = unitX - this.x;
        const dy = unitY - this.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        return distance < (this.size / 2 + unitRadius);
    }
}

// 유닛 클래스
class Unit {
    constructor(type, x, y, isEnemy = false) {
        this.type = type;
        this.x = x;
        this.y = y;
        this.health = UNIT_TYPES[type].health;
        this.maxHealth = UNIT_TYPES[type].health;
        this.damage = UNIT_TYPES[type].damage;
        this.speed = UNIT_TYPES[type].speed;
        this.range = UNIT_TYPES[type].range;
        this.isEnemy = isEnemy;
        this.target = null;
        this.lastAttackTime = 0;
        this.isMoving = true;
        this.emoji = UNIT_TYPES[type].emoji;
        this.targetY = y;
        this.legAngle = 0;  // 다리 각도
        this.legSpeed = 0.2;  // 다리 움직임 속도
        this.radius = 10;  // 충돌 감지를 위한 반지름
        this.detourAngle = 0;  // 우회 각도
        this.isDetouring = false;  // 우회 중인지 여부
        this.detourTimer = 0;  // 우회 타이머
        this.baseSpeed = UNIT_TYPES[type].speed;  // 기본 속도 저장
        this.currentSpeed = this.baseSpeed;       // 현재 속도
    }

    // 바위와의 충돌 체크
    checkRockCollision(newX, newY) {
        for (let rock of rocks) {
            const dx = newX - rock.x;
            const dy = newY - rock.y;
            const distance = Math.sqrt(dx * dx + dy * dy);
            const minDistance = this.radius + rock.size / 2;
            
            if (distance < minDistance) {
                return true;  // 충돌 발생
            }
        }
        return false;  // 충돌 없음
    }

    // 우회 경로 찾기
    findDetourPath(newX, newY) {
        if (!this.isDetouring) {
            this.isDetouring = true;
            this.detourAngle = Math.random() * Math.PI * 2;  // 랜덤한 방향으로 우회
            this.detourTimer = 30;  // 우회 지속 시간
        }

        // 우회 각도에 따라 이동
        const detourX = this.x + Math.cos(this.detourAngle) * this.speed;
        const detourY = this.y + Math.sin(this.detourAngle) * this.speed;

        // 우회 타이머 감소
        this.detourTimer--;
        if (this.detourTimer <= 0) {
            this.isDetouring = false;
        }

        return { x: detourX, y: detourY };
    }

    draw() {
        // 이모티콘 그리기
        ctx.font = '15px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        
        // 다리 그리기
        if (this.isMoving) {
            ctx.save();
            ctx.translate(this.x, this.y);
            if (this.isEnemy) {
                ctx.scale(-1, 1);
            }
            
            // 왼쪽 다리
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(-3, 5 + Math.sin(this.legAngle) * 3);
            ctx.strokeStyle = '#000';
            ctx.lineWidth = 2;
            ctx.stroke();
            
            // 오른쪽 다리
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(3, 5 + Math.sin(this.legAngle + Math.PI) * 3);
            ctx.strokeStyle = '#000';
            ctx.lineWidth = 2;
            ctx.stroke();
            
            ctx.restore();
        }
        
        // 적군은 이모티콘을 뒤집어서 표시
        if (this.isEnemy) {
            ctx.save();
            ctx.translate(this.x, this.y);
            ctx.scale(-1, 1);
            ctx.fillText(this.emoji, 0, 0);
            ctx.restore();
        } else {
            ctx.fillText(this.emoji, this.x, this.y);
        }

        // 체력바 그리기
        const healthBarWidth = 15;
        const healthBarHeight = 3;
        const healthPercentage = this.health / this.maxHealth;
        
        ctx.fillStyle = '#ff0000';
        ctx.fillRect(this.x - healthBarWidth/2, this.y - 12, healthBarWidth, healthBarHeight);
        ctx.fillStyle = '#00ff00';
        ctx.fillRect(this.x - healthBarWidth/2, this.y - 12, healthBarWidth * healthPercentage, healthBarHeight);

        // 디버그용 충돌 범위 표시 (필요시 주석 해제)
        /*
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(255, 0, 0, 0.3)';
        ctx.stroke();
        */

        // 디버그용 우회 경로 표시 (필요시 주석 해제)
        /*
        if (this.isDetouring) {
            ctx.beginPath();
            ctx.moveTo(this.x, this.y);
            ctx.lineTo(
                this.x + Math.cos(this.detourAngle) * 20,
                this.y + Math.sin(this.detourAngle) * 20
            );
            ctx.strokeStyle = 'rgba(0, 255, 0, 0.3)';
            ctx.stroke();
        }
        */
    }

    update() {
        if (isGameOver) return;

        // 다리 애니메이션 업데이트
        if (this.isMoving) {
            this.legAngle += this.legSpeed;
        }

        // 타겟이 없으면 새로운 타겟 찾기
        if (!this.target || this.target.health <= 0) {
            this.findTarget();
        }

        // 타겟이 있으면 전투
        if (this.target && this.target.health > 0) {
            const distance = Math.abs(this.x - this.target.x);
            
            // 공격 범위 안에 있으면 공격
            if (distance <= this.range) {
                this.isMoving = false;
                const currentTime = Date.now();
                if (currentTime - this.lastAttackTime >= UNIT_TYPES[this.type].cooldown) {
                    this.attack(this.target);
                    this.lastAttackTime = currentTime;
                }
            } 
            // 공격 범위 밖이면 이동
            else {
                this.isMoving = true;
                this.moveTowardsTarget();
            }
        } 
        // 타겟이 없으면 기본 이동
        else {
            this.isMoving = true;
            this.moveForward();
        }
    }

    // 크레이터 체크 및 속도 조정
    checkCraters() {
        this.currentSpeed = this.baseSpeed;  // 기본 속도로 초기화
        for (let crater of craters) {
            if (crater.isUnitInCrater(this.x, this.y, this.radius)) {
                this.currentSpeed = this.baseSpeed * 0.5;  // 속도 절반으로 감소
                break;
            }
        }
    }

    moveForward() {
        this.checkCraters();  // 크레이터 체크 및 속도 조정
        
        if (this.isEnemy) {
            const newX = this.x - this.currentSpeed;
            if (this.checkRockCollision(newX, this.y)) {
                const detour = this.findDetourPath(newX, this.y);
                if (!this.checkRockCollision(detour.x, detour.y)) {
                    this.x = detour.x;
                    this.y = detour.y;
                }
            } else {
                this.x = newX;
            }
        } else {
            const newX = this.x + this.currentSpeed;
            if (this.checkRockCollision(newX, this.y)) {
                const detour = this.findDetourPath(newX, this.y);
                if (!this.checkRockCollision(detour.x, detour.y)) {
                    this.x = detour.x;
                    this.y = detour.y;
                }
            } else {
                this.x = newX;
            }
        }

        // y축 위치 조정
        const yDiff = this.targetY - this.y;
        if (Math.abs(yDiff) > 1) {
            const newY = this.y + Math.sign(yDiff) * this.currentSpeed * 0.5;
            if (this.checkRockCollision(this.x, newY)) {
                const detour = this.findDetourPath(this.x, newY);
                if (!this.checkRockCollision(detour.x, detour.y)) {
                    this.x = detour.x;
                    this.y = detour.y;
                }
            } else {
                this.y = newY;
            }
        }
    }

    moveTowardsTarget() {
        this.checkCraters();  // 크레이터 체크 및 속도 조정
        
        if (this.target) {
            const direction = this.target.x - this.x;
            const moveAmount = Math.sign(direction) * this.currentSpeed;
            const newX = this.x + moveAmount;
            
            if (this.checkRockCollision(newX, this.y)) {
                const detour = this.findDetourPath(newX, this.y);
                if (!this.checkRockCollision(detour.x, detour.y)) {
                    this.x = detour.x;
                    this.y = detour.y;
                }
            } else {
                this.x = newX;
            }

            // y축 위치 조정
            const yDiff = this.targetY - this.y;
            if (Math.abs(yDiff) > 1) {
                const newY = this.y + Math.sign(yDiff) * this.currentSpeed * 0.5;
                if (this.checkRockCollision(this.x, newY)) {
                    const detour = this.findDetourPath(this.x, newY);
                    if (!this.checkRockCollision(detour.x, detour.y)) {
                        this.x = detour.x;
                        this.y = detour.y;
                    }
                } else {
                    this.y = newY;
                }
            }
        }
    }

    findTarget() {
        const targetList = this.isEnemy ? units : enemyUnits;
        let closestTarget = null;
        let closestDistance = Infinity;

        // 먼저 적 유닛을 찾음
        for (let unit of targetList) {
            if (unit.health > 0) {
                const distance = Math.abs(this.x - unit.x);
                if (distance < closestDistance) {
                    closestDistance = distance;
                    closestTarget = unit;
                }
            }
        }

        // 적 유닛이 없으면 성을 타겟으로 설정
        if (!closestTarget) {
            const castle = this.isEnemy ? playerCastle : enemyCastle;
            const distance = Math.abs(this.x - castle.x);
            if (distance <= this.range) {
                closestTarget = castle;
            }
        }

        this.target = closestTarget;
    }

    attack(target) {
        if (this.type === 'melee') {
            // 근접 공격
            if (target instanceof Castle) {
                target.takeDamage(this.damage * 0.5); // 성에 대한 데미지는 50%로 감소
            } else {
                target.health -= this.damage;
                if (target.health <= 0) {
                    target.health = 0;
                    this.target = null;
                }
            }
        } else {
            // 원거리 공격 (궁병, 포병)
            const projectileSize = this.type === 'archer' ? 5 : 7.5;
            const projectileSpeed = this.type === 'archer' ? 8 : 6;
            const damage = target instanceof Castle ? this.damage * 0.5 : this.damage; // 성에 대한 데미지는 50%로 감소
            projectiles.push(new Projectile(
                this.x,
                this.y,
                target.x,
                target.y,
                projectileSpeed,
                damage,
                projectileSize,
                this.isEnemy
            ));
        }
    }
}

// 폭발 효과 클래스
class Explosion {
    constructor(x, y, size) {
        this.x = x;
        this.y = y;
        this.size = size;
        this.maxSize = size * 2;
        this.currentSize = size;
        this.alpha = 1;
        this.isFinished = false;
    }

    update() {
        this.currentSize += 2;
        this.alpha -= 0.05;
        if (this.alpha <= 0) {
            this.isFinished = true;
        }
    }

    draw() {
        ctx.save();
        ctx.globalAlpha = this.alpha;
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.currentSize, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255, ${Math.floor(Math.random() * 100)}, 0, ${this.alpha})`;
        ctx.fill();
        ctx.restore();
    }
}

// 와치타워 클래스
class WatchTower {
    constructor(x, y, isEnemy = false) {
        this.x = x;
        this.y = y;
        this.width = 20;
        this.height = 30;
        this.isEnemy = isEnemy;
        this.lastAttackTime = 0;
        this.attackCooldown = 2000; // 2초마다 공격
        this.range = 300; // 공격 범위
        this.damage = isEnemy ? 10 * enemyPowerMultiplier : 10;  // 적 와치타워의 공격력 증가
    }

    draw() {
        // 와치타워 그리기
        ctx.fillStyle = this.isEnemy ? '#ff0000' : '#0000ff';
        ctx.fillRect(this.x - this.width/2, this.y - this.height/2, this.width, this.height);
        
        // 와치타워 이모티콘
        ctx.font = '20px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('🏰', this.x, this.y);
    }

    update() {
        if (isGameOver) return;

        const currentTime = Date.now();
        if (currentTime - this.lastAttackTime >= this.attackCooldown) {
            this.findAndAttackTarget();
            this.lastAttackTime = currentTime;
        }
    }

    findAndAttackTarget() {
        const targetList = this.isEnemy ? units : enemyUnits;
        let closestTarget = null;
        let closestDistance = Infinity;

        // 가장 가까운 적 찾기
        for (let unit of targetList) {
            if (unit.health > 0) {
                const dx = this.x - unit.x;
                const dy = this.y - unit.y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                
                if (distance < this.range && distance < closestDistance) {
                    closestDistance = distance;
                    closestTarget = unit;
                }
            }
        }

        // 적이 없으면 성을 공격
        if (!closestTarget) {
            const castle = this.isEnemy ? playerCastle : enemyCastle;
            const dx = this.x - castle.x;
            const dy = this.y - castle.y;
            const distance = Math.sqrt(dx * dx + dy * dy);
            
            if (distance < this.range) {
                closestTarget = castle;
            }
        }

        // 타겟이 있으면 공격
        if (closestTarget) {
            projectiles.push(new Projectile(
                this.x,
                this.y - this.height/2,
                closestTarget.x,
                closestTarget.y,
                8,
                this.damage,
                4,
                this.isEnemy
            ));
        }
    }
}

// 바위 클래스
class Rock {
    constructor(x, y, size) {
        this.x = x;
        this.y = y;
        this.size = size;
        this.emoji = '🪨';
    }

    draw() {
        ctx.font = `${this.size}px Arial`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(this.emoji, this.x, this.y);
    }
}

// 바위 생성 함수
function createRocks() {
    rocks = [];
    const rockCount = 20;  // 바위 개수
    const minSize = 10;    // 최소 크기
    const maxSize = 30;    // 최대 크기
    
    for (let i = 0; i < rockCount; i++) {
        const x = Math.random() * (canvas.width - 100) + 50;  // 성 주변 제외
        const y = Math.random() * (canvas.height - 100) + 50; // 상하단 여백
        const size = Math.random() * (maxSize - minSize) + minSize;
        rocks.push(new Rock(x, y, size));
    }
}

// 크레이터 생성 함수
function createCraters() {
    craters = [];
    const craterCount = 15;  // 크레이터 개수
    const minSize = 15;      // 최소 크기
    const maxSize = 25;      // 최대 크기
    
    for (let i = 0; i < craterCount; i++) {
        const x = Math.random() * (canvas.width - 100) + 50;  // 성 주변 제외
        const y = Math.random() * (canvas.height - 100) + 50; // 상하단 여백
        const size = Math.random() * (maxSize - minSize) + minSize;
        craters.push(new Crater(x, y, size));
    }
}

// 게임 초기화
function init() {
    // 게임 상태 초기화
    units = [];
    enemyUnits = [];
    projectiles = [];
    explosions = [];
    watchTowers = [];  // 와치타워 배열 초기화
    rocks = [];  // 바위 배열 초기화
    craters = [];  // 크레이터 배열 초기화
    lastSpawnTime = { melee: 0, archer: 0, cannon: 0 };
    isGameOver = false;

    // 바위 생성
    createRocks();
    
    // 크레이터 생성
    createCraters();

    // 성 생성
    playerCastle = new Castle(30);
    enemyCastle = new Castle(canvas.width - 30, true);

    // 와치타워 생성
    // 플레이어 와치타워
    watchTowers.push(new WatchTower(30, canvas.height * 0.3));
    watchTowers.push(new WatchTower(30, canvas.height * 0.7));
    // 적 와치타워
    watchTowers.push(new WatchTower(canvas.width - 30, canvas.height * 0.3, true));
    watchTowers.push(new WatchTower(canvas.width - 30, canvas.height * 0.7, true));

    // 적 유닛 자동 생성
    setInterval(() => {
        if (!isGameOver) {
            const types = Object.keys(UNIT_TYPES);
            const randomType = types[Math.floor(Math.random() * types.length)];
            spawnEnemyUnit(randomType);
        }
    }, 5000);

    // 게임 루프 시작
    if (gameLoop) {
        clearInterval(gameLoop);
    }
    gameLoop = setInterval(() => {
        update(playerCastle, enemyCastle);
    }, 1000/60);

    // 버튼 활성화
    const buttons = document.querySelectorAll('.unit-button');
    buttons.forEach(button => button.disabled = false);
}

// 유닛 생성
function spawnUnit(type) {
    const currentTime = Date.now();
    if (currentTime - lastSpawnTime[type] < UNIT_TYPES[type].cooldown) {
        return;
    }

    // y축 위치를 랜덤하게 분산
    const yPositions = [canvas.height * 0.3, canvas.height * 0.5, canvas.height * 0.7];
    const randomY = yPositions[Math.floor(Math.random() * yPositions.length)];
    
    units.push(new Unit(type, 50, randomY));
    lastSpawnTime[type] = currentTime;
    updateButtons();
}

// 적 유닛 생성
function spawnEnemyUnit(type) {
    // y축 위치를 랜덤하게 분산
    const yPositions = [canvas.height * 0.3, canvas.height * 0.5, canvas.height * 0.7];
    const randomY = yPositions[Math.floor(Math.random() * yPositions.length)];
    
    const unit = new Unit(type, canvas.width - 50, randomY, true);
    // 적 유닛의 공격력 증가
    unit.damage = Math.floor(UNIT_TYPES[type].damage * enemyPowerMultiplier);
    enemyUnits.push(unit);
}

// 버튼 상태 업데이트
function updateButtons() {
    const buttons = {
        melee: document.getElementById('meleeBtn'),
        archer: document.getElementById('archerBtn'),
        cannon: document.getElementById('cannonBtn')
    };

    for (let type in buttons) {
        const button = buttons[type];
        const currentTime = Date.now();
        const cooldown = UNIT_TYPES[type].cooldown;

        if (currentTime - lastSpawnTime[type] < cooldown) {
            button.disabled = true;
            const remainingTime = Math.ceil((cooldown - (currentTime - lastSpawnTime[type])) / 1000);
            button.textContent = `${type} (${remainingTime}s)`;
        } else {
            button.disabled = false;
            button.textContent = type;
        }
    }
}

// 발사체 충돌 체크
function checkProjectileCollisions(playerCastle, enemyCastle) {
    for (let i = projectiles.length - 1; i >= 0; i--) {
        const projectile = projectiles[i];
        const targetList = projectile.isEnemy ? units : enemyUnits;
        let hit = false;

        // 유닛과의 충돌 체크
        for (let unit of targetList) {
            if (unit.health > 0) {
                const dx = projectile.x - unit.x;
                const dy = projectile.y - unit.y;
                const distance = Math.sqrt(dx * dx + dy * dy);

                if (distance < 20) {
                    unit.health -= projectile.damage;
                    if (unit.health <= 0) {
                        unit.health = 0;
                    }
                    // 폭발 효과 추가
                    explosions.push(new Explosion(projectile.x, projectile.y, projectile.size * 2));
                    projectiles.splice(i, 1);
                    hit = true;
                    break;
                }
            }
        }

        // 성과의 충돌 체크
        if (!hit) {
            const castle = projectile.isEnemy ? playerCastle : enemyCastle;
            const dx = projectile.x - castle.x;
            const dy = projectile.y - castle.y;
            const distance = Math.sqrt(dx * dx + dy * dy);

            if (distance < 50) {
                castle.takeDamage(projectile.damage);
                // 폭발 효과 추가
                explosions.push(new Explosion(projectile.x, projectile.y, projectile.size * 3));
                projectiles.splice(i, 1);
            }
        }

        // 화면 밖으로 나간 발사체 제거
        if (projectile.isOutOfBounds()) {
            projectiles.splice(i, 1);
        }
    }
}

// 게임 오버 처리
function gameOver(isEnemyWin) {
    isGameOver = true;
    clearInterval(gameLoop);
    
    // 게임 오버 메시지 표시
    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    ctx.fillStyle = '#ffffff';
    ctx.font = '48px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(isEnemyWin ? '패배!' : '승리!', canvas.width/2, canvas.height/2 - 50);
    
    // 승리 시 적 공격력 증가
    if (!isEnemyWin) {
        enemyPowerMultiplier += 0.5;
        ctx.font = '24px Arial';
        ctx.fillText(`다음 게임: 적 공격력 ${enemyPowerMultiplier.toFixed(1)}배`, canvas.width/2, canvas.height/2);
    }
    
    // 재시작 버튼 생성
    const restartButton = document.createElement('button');
    restartButton.textContent = '재시작';
    restartButton.style.position = 'absolute';
    restartButton.style.left = '50%';
    restartButton.style.top = '60%';
    restartButton.style.transform = 'translate(-50%, -50%)';
    restartButton.style.padding = '10px 20px';
    restartButton.style.fontSize = '20px';
    restartButton.style.cursor = 'pointer';
    restartButton.style.backgroundColor = '#4CAF50';
    restartButton.style.color = 'white';
    restartButton.style.border = 'none';
    restartButton.style.borderRadius = '5px';
    
    restartButton.onclick = () => {
        document.body.removeChild(restartButton);
        init();
    };
    
    document.body.appendChild(restartButton);
    
    // 버튼 비활성화
    const buttons = document.querySelectorAll('.unit-button');
    buttons.forEach(button => button.disabled = true);
}

// 게임 업데이트
function update(playerCastle, enemyCastle) {
    // 화면 클리어
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // 바위 그리기
    for (let rock of rocks) {
        rock.draw();
    }

    // 크레이터 그리기
    for (let crater of craters) {
        crater.draw();
    }

    // 성 그리기
    playerCastle.draw();
    enemyCastle.draw();

    // 와치타워 업데이트 및 그리기
    for (let tower of watchTowers) {
        tower.update();
        tower.draw();
    }

    // 발사체 업데이트
    for (let projectile of projectiles) {
        projectile.update();
        projectile.draw();
    }

    // 폭발 효과 업데이트 및 그리기
    for (let i = explosions.length - 1; i >= 0; i--) {
        explosions[i].update();
        explosions[i].draw();
        if (explosions[i].isFinished) {
            explosions.splice(i, 1);
        }
    }

    // 발사체 충돌 체크
    checkProjectileCollisions(playerCastle, enemyCastle);

    // 유닛 업데이트 및 그리기
    for (let unit of [...units, ...enemyUnits]) {
        if (unit.health > 0) {
            unit.update();
            unit.draw();
        }
    }

    // 버튼 상태 업데이트
    updateButtons();
}

// 게임 시작
init(); 